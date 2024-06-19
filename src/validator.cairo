use starknet::ContractAddress;

#[starknet::interface]
trait IValidatorTrait <TContractState> {
    fn stake(ref self: TContractState, amount: u128) -> bool;
    fn unstake(ref self: TContractState) -> bool;
    fn validate_campaign(ref self: TContractState, campaign_id: u32) -> bool;
    fn get_all_validators(self: @TContractState) -> Array<Validator::ValidatorInfo>;
    fn get_active_validators(self: @TContractState) -> Array<Validator::ValidatorInfo>;
    fn get_campaign_validators(self: @TContractState, campaign_id: u32) -> Array<u32>;
    fn get_validator_id(self: @TContractState, address: ContractAddress) -> u32;
    fn get_validator(self: @TContractState, validator_id: u32) -> Validator::ValidatorInfo;
}

#[starknet::contract]
pub mod Validator {
    use starknet::{ContractAddress, get_caller_address, get_contract_address};
    use starknet::syscalls::transfer;

    #[storage]
    struct Storage {
        validators: LegacyMap::<u32, ValidatorInfo>,  // validator_id to ValidatorInfo
        returning_validator: LegacyMap::<ContractAddress, bool>,
        total_validators: u32,
        total_active_validators: u32,
        campaign_validations: LegacyMap::<u32, Array<u32>>,  // campaign_id to list of validator_ids
        validator_stakes: LegacyMap::<u32, u128>,  // validator_id to staked amount
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
        pub validated_campaigns: Array<u32>,
    }

    #[constructor]
    fn constructor(ref self: ContractState) {
        self.total_validators.write(0);
        self.total_active_validators.write(0);
        self.stake_amount.write(100);
        self.total_stakes.write(0);
    }

    #[abi(embed_v0)]
    impl ValidatorImpl of super::IValidatorTrait<ContractState> {
        fn stake(ref self: ContractState, amount: u128) -> bool {
            assert!(amount >= self.stake_amount.read(), "Staked amount is less than minimum stake amount");

            let caller = get_caller_address();
            let contract_address = get_contract_address();

            if self.returning_validator.read(caller) {
                let validator_id = self.get_validator_id(caller);

                let mut validator_info = self.validators.read(validator_id);
                validator_info.stake += amount;
                validator_info.status = Status::Active;
                self.validators.write(validator_id, validator_info);
                self.validator_stakes.write(validator_id, amount);

                Event::Staked(Staked {
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
                    validated_campaigns: ArrayTrait::<u32>::new(),
                };

                self.total_validators.write(validator_id);
                self.returning_validator.write(caller, true);
                self.validators.write(validator_id, validator_info);
                self.validator_stakes.write(validator_id, amount);

                Event::Staked(Staked {
                    validator_id: validator_id,
                    stake: amount,
                });
            }

            self.total_active_validators.write(self.total_active_validators.read() + 1);

            // Perform the transfer
            transfer(contract_address, amount).unwrap();

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

            // Perform the transfer
            transfer(caller, amount).unwrap();

            // Update the contract's balance
            let current_balance = self.total_stakes.read();
            self.total_stakes.write(current_balance - stake);

            Event::Unstaked(Unstaked {
                validator_id: validator_id,
                stake: stake,
            });
            true
        }

        fn validate_campaign(ref self: ContractState, campaign_id: u32) -> bool {
            let caller = get_caller_address();
            let validator_id = self.get_validator_id(caller);

            let mut validator_info = self.validators.read(validator_id);
            validator_info.validated_campaigns.append(campaign_id);

            self.validators.write(validator_id, validator_info);

            let mut campaign_validators = self.campaign_validations.read(campaign_id);
            campaign_validators.append(validator_id);

            self.campaign_validations.write(campaign_id, campaign_validators);

            Event::CampaignValidated(CampaignValidated {
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

        fn get_campaign_validators(self: @ContractState, campaign_id: u32) -> Array<u32> {
            self.campaign_validations.read(campaign_id)
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
    }
}