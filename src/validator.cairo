use starknet::ContractAddress;

#[starknet::interface]
trait IValidatorTrait <TContractState> {
    fn stake(ref self: TContractState, amount: u128) -> bool;
    fn unstake(ref self: TContractState) -> bool;
    fn validate_campaign(ref self: TContractState, campaign_id: u32) -> bool;
    fn get_validators(self: @TContractState) -> Array<Validator::ValidatorInfo>;
    fn get_campaign_validators(self: @TContractState, campaign_id: u32) -> Array<u32>;
    fn get_validator_id(self: @TContractState, address: ContractAddress) -> u32;
    fn get_validator(self: @TContractState, validator_id: u32) -> Validator::ValidatorInfo;
}

#[starknet::contract]
mod Validator {
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
        pub stake: u32,
    }

    #[derive(Drop, starknet::Event)]
    pub struct Unstaked {
        #[key]
        pub validator_id: u32,
        pub stake: u32,
    }

    #[derive(Drop, starknet::Event)]
    pub struct CampaignValidated {
        #[key]
        pub validator_id: u32,
        #[key]
        pub campaign_id: u32,
    }

    #[derive(Copy, Drop, Clone, Serde, starknet::Contract)]
    enum Status {
        Inactive,
        Active,
        Banned
    }

    #[derive(Drop, Serde, starknet::Store)]
    struct ValidatorInfo {
        validator_id: u32,
        stake: u32,
        address: ContractAddress,
        status: Status,
        validated_campaigns: Array<u32>, // List of campaign IDs validated by this validator
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

            if self.returning_validator(caller) {
                let validator_id = self.get_validator_id.read(caller);

                let mut validator_info = self.validators.read(validator_id);
                validator_info.stake += amount;
                validator_info.status = Status::Active;
            } else {
                let current_validator_id = self.total_validators.read();
                let validator_id = current_validator_id + 1;

                let validator_info = ValidatorInfo {
                    validator_id: validator_id,
                    stake: amount,
                    address: caller,
                    status: Status::Active,
                    validated_campaigns: Array::new(),
                };

                self.total_validators.write(validator_id);
                self.returning_validator(caller) = true;
            }

            self.validators.write(validator_id, validator_info);
            self.validator_stakes.write(new_validator_id, stake);
            self.total_active_validators.write(self.total_active_validators.read() + 1);

            // Perform the transfer
            transfer(contract_address, amount).unwrap();

            // Update the contract's balance
            let current_balance = self.total_stakes.read();
            self.total_stakes.write(current_balance + amount);

            Event::Staked(Staked {
                validator_id: validator_id,
                stake: stake,
            });
            true
        }

        fn unstake(ref self: ContractState) -> bool {
            let caller = get_caller_address();
            let validator_id = self.get_validator_id.read(caller);

            let mut validator_info = self.validators.read(validator_id);
            let stake = validator_info.stake;
            validator_info.stake = 0;
            validator_info.status = Status::Inactive;

            self.validators.write(validator_id, validator_info);
            self.validator_stakes.write(validator_id, 0);
            self.total_active_validators.write(self.total_active_validators.read() - 1);

            // Perform the transfer
            transfer(contract_address, amount).unwrap();

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
            let validator_id = self.get_validator_id.read(caller);

            let mut validator_info = self.validators.read(validator_id);
            validator_info.validated_campaigns.push(campaign_id);

            self.validators.write(validator_id, validator_info);

            let mut campaign_validators = self.campaign_validations.read(campaign_id);
            campaign_validators.push(validator_id);

            self.campaign_validations.write(campaign_id, campaign_validators);

            Event::CampaignValidated(CampaignValidated {
                validator_id: validator_id,
                campaign_id: campaign_id,
            });
            true
        }
    }
}