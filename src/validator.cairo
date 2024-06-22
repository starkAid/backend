use starknet::ContractAddress;

#[starknet::interface]
pub trait IValidator <TContractState> {
    fn stake(ref self: TContractState, amount: u128) -> bool;
    fn unstake(ref self: TContractState) -> bool;
    fn validate_campaign(ref self: TContractState, campaign_id: u32, validator_address: ContractAddress) -> bool;
    fn get_all_validators(self: @TContractState) -> Array<Validator::ValidatorInfo>;
    fn get_active_validators(self: @TContractState) -> Array<Validator::ValidatorInfo>;
    fn get_active_validators_count(self: @TContractState) -> u32;
    fn get_campaign_validators(self: @TContractState, campaign_id: u32) -> Array<u32>;
    fn get_validator_id(self: @TContractState, address: ContractAddress) -> u32;
    fn get_validator(self: @TContractState, validator_id: u32) -> Validator::ValidatorInfo;
    fn is_validator(ref self: TContractState, address: ContractAddress) -> bool;
    fn get_total_staked(self: @TContractState) -> u128;
}

#[starknet::contract]
pub mod Validator {
    use starknet::{ContractAddress, contract_address_const, get_caller_address, get_contract_address};
    use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};

    #[storage]
    struct Storage {
        validators: LegacyMap::<u32, ValidatorInfo>,  // validator_id to ValidatorInfo
        returning_validator: LegacyMap::<ContractAddress, bool>,
        total_validators: u32,
        total_active_validators: u32,
        campaign_validators_count: LegacyMap::<u32, u32>, // campaign_id to campaign_validators_count
        campaign_validators: LegacyMap::<(u32, u32), u32>,  // (campaign_id, campaign_validators_count) to campaign_validators_id
        is_campaign_validated: LegacyMap::<(u32, u32), bool>, // (validator_id, campaign_id) to bool
        validator_stakes: LegacyMap::<u32, u128>,  // validator_id to staked amount
        validator_campaign_count: LegacyMap::<u32, u32>,  // validator_id to no of validations
        validated_campaigns: LegacyMap::<(u32, u32), u32>, // (validator_id, validator_campaign_count) to campaign_id
        stake_amount: u128,
        total_stakes: u128,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        Staked: Staked,
        Unstaked: Unstaked,
        CampaignValidated: CampaignValidated,
    }

    #[derive(Drop, starknet::Event)]
    pub struct Staked {
        #[key]
        pub validator_id: u32,
        #[key]
        pub stake: u128,
    }

    #[derive(Drop, starknet::Event)]
    pub struct Unstaked {
        #[key]
        pub validator_id: u32,
        #[key]
        pub stake: u128,
    }

    #[derive(Drop, starknet::Event)]
    pub struct CampaignValidated {
        #[key]
        pub validator_id: u32,
        #[key]
        pub campaign_id: u32,
    }

    #[derive(Copy, Drop, Clone, Serde, PartialEq, starknet::Store)]
    enum Status {
        Inactive,
        Active,
        Banned
    }

    #[derive(Drop, Serde, starknet::Store)]
    pub struct ValidatorInfo {
        pub validator_id: u32,
        pub stake: u128,
        pub address: ContractAddress,
        pub status: Status,
    }

    #[constructor]
    fn constructor(ref self: ContractState) {
        self.total_validators.write(0);
        self.total_active_validators.write(0);
        self.stake_amount.write(10);
        self.total_stakes.write(0);
    }

    #[abi(embed_v0)]
    impl ValidatorImpl of super::IValidator<ContractState> {
        fn stake(ref self: ContractState, amount: u128) -> bool {
            assert!(amount >= self.stake_amount.read(), "Staked amount is less than minimum stake amount");

            let caller = get_caller_address();
            let validator_contract_address = get_contract_address();

            if self.returning_validator.read(caller) {
                let validator_id = self.get_validator_id(caller);

                let mut validator_info = self.validators.read(validator_id);
                validator_info.stake += amount;
                validator_info.status = Status::Active;
                self.validators.write(validator_id, validator_info);
                self.validator_stakes.write(validator_id, amount);

                self.emit(Staked {
                    validator_id: validator_id,
                    stake: amount,
                });
            } else {
                let current_validator_id = self.total_validators.read();
                let validator_id = current_validator_id + 1;

                let validator_info = ValidatorInfo {
                    validator_id: validator_id,
                    stake: amount,
                    address: caller,
                    status: Status::Active,
                };

                self.total_validators.write(validator_id);
                self.returning_validator.write(caller, true);
                self.validators.write(validator_id, validator_info);
                self.validator_stakes.write(validator_id, amount);

                self.emit(Staked {
                    validator_id: validator_id,
                    stake: amount,
                });
            }

            self.total_active_validators.write(self.total_active_validators.read() + 1);

            self._transfer_from(caller, validator_contract_address, amount.into());

            // Update the contract's balance
            let current_balance = self.total_stakes.read();
            self.total_stakes.write(current_balance + amount);

            true
        }

        fn unstake(ref self: ContractState) -> bool {
            let caller = get_caller_address();
            let validator_id = self.get_validator_id(caller);

            let mut validator_info = self.validators.read(validator_id);
            let stake = validator_info.stake;
            validator_info.stake = 0;
            validator_info.status = Status::Inactive;

            self.validators.write(validator_id, validator_info);
            self.validator_stakes.write(validator_id, 0);
            self.total_active_validators.write(self.total_active_validators.read() - 1);

            self._transfer(caller, stake.into());

            // Update the contract's balance
            let current_balance = self.total_stakes.read();
            self.total_stakes.write(current_balance - stake);

            self.emit(Unstaked {
                validator_id: validator_id,
                stake: stake,
            });
            true
        }

        fn validate_campaign(ref self: ContractState, campaign_id: u32, validator_address: ContractAddress) -> bool {
            let validator_id = self.get_validator_id(validator_address);

            assert!(self.validators.read(validator_id).status == Status::Active, "Validator is not active");
            assert!(!self.is_campaign_validated.read((validator_id, campaign_id)), "Campaign already validated");

            let count = (self.validator_campaign_count.read(validator_id) + 1);
            self.validated_campaigns.write((validator_id, count), campaign_id);
            self.validator_campaign_count.write(validator_id, count);

            let campaign_validator_count = (self.campaign_validators_count.read(campaign_id) + 1);
            self.campaign_validators.write((campaign_id, campaign_validator_count), validator_id);
            self.campaign_validators_count.write(campaign_id, campaign_validator_count);

            self.is_campaign_validated.write((validator_id, campaign_id), true);

            self.emit(CampaignValidated {
                validator_id: validator_id,
                campaign_id: campaign_id,
            });
            
            true
        }

        fn get_all_validators(self: @ContractState) -> Array<ValidatorInfo> {
            let mut validators = ArrayTrait::<ValidatorInfo>::new();
            let mut count = self.total_validators.read();

            while count > 0 {
                let validator = self.validators.read(count);
                validators.append(validator);
                count -= 1;
            };
            
            validators
        }

        fn get_active_validators(self: @ContractState) -> Array<ValidatorInfo> {
            let mut active_validators = ArrayTrait::<ValidatorInfo>::new();
            let mut count = self.total_validators.read();

            while count > 0 {
                let validator = self.validators.read(count);

                if validator.status == Status::Active {
                    active_validators.append(validator);
                }

                count -= 1;
            };
            
            active_validators
        }

        fn get_active_validators_count(self: @ContractState) -> u32 {
            self.total_active_validators.read()
        }

        fn get_campaign_validators(self: @ContractState, campaign_id: u32) -> Array<u32> {
            let mut campaign_validators = ArrayTrait::<u32>::new();
            let mut count = self.campaign_validators_count.read(campaign_id);

            while count > 0 {
                let validator_id = self.campaign_validators.read((campaign_id, count));
                campaign_validators.append(validator_id);
                count -= 1;
            };

            campaign_validators
        }

        fn get_validator_id(self: @ContractState, address: ContractAddress) -> u32 {
            let mut validator_id = 0;
            let mut count = self.total_validators.read();

            while count > 0 {
                let validator = self.validators.read(count);

                if validator.address == address {
                    validator_id = validator.validator_id;
                    break;
                }

                count -= 1;
            };

            validator_id
        }

        fn get_validator(self: @ContractState, validator_id: u32) -> ValidatorInfo {
            self.validators.read(validator_id)
        }

        fn is_validator(ref self: ContractState, address: ContractAddress) -> bool {
            let mut is_validator = false;
            let mut count = self.total_validators.read();

            while count > 0 {
                let validator = self.validators.read(count);

                if validator.address == address {
                    is_validator = true;
                    break;
                }

                count -= 1;
            };

            is_validator
        }

        fn get_total_staked(self: @ContractState) -> u128 {
            self.total_stakes.read()
        }
    }

    #[generate_trait]
    impl ERC20Impl of ERC20Trait {
        fn _transfer_from(ref self: ContractState, sender: ContractAddress, recipient: ContractAddress, amount: u128) {
            let eth_dispatcher = IERC20Dispatcher {
                contract_address: contract_address_const::<0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d>() // STRK token Contract Address
            };
            assert(eth_dispatcher.balance_of(sender) >= amount.into(), 'insufficient funds');

            // eth_dispatcher.approve(validator_contract_address, amount.into()); This is wrong as it is the validator contract trying to approve itself
            let success = eth_dispatcher.transfer_from(sender, recipient, amount.into());
            assert(success, 'ERC20 transfer_from failed!');
        }

        fn _transfer(ref self: ContractState, recipient: ContractAddress, amount: u128) {
            let eth_dispatcher = IERC20Dispatcher {
                contract_address: contract_address_const::<0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d>() // STRK token Contract Address
            };
            let success = eth_dispatcher.transfer(recipient, amount.into());
            assert(success, 'ERC20 transfer failed!');
        }
    }
}