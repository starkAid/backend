use starknet::ContractAddress;

#[starknet::interface]
trait IValidatorTrait <TContractState> {
    fn stake(ref self: TContractState, amount: u32) -> bool;
    fn unstake(ref self: TContractState) -> bool;
    fn validate_campaign(ref self: TContractState, campaign_id: u32) -> bool;
    fn get_validators(self: @TContractState) -> Array<Validator::ValidatorInfo>;
    fn get_campaign_validators(self: @TContractState, campaign_id: u32) -> Array<u32>;
    fn get_validator(self: @TContractState, validator_id: u32) -> Validator::ValidatorInfo;
}

#[starknet::contract]
mod Validator {
    use starknet::{ContractAddress, get_caller_address};

    #[storage]
    struct Storage {
        validators: LegacyMap::<u32, ValidatorInfo>,  // validator_id to ValidatorInfo
        total_validators: u32,
        campaign_validations: LegacyMap::<u32, Array<u32>>,  // campaign_id to list of validator_ids
        validator_stakes: LegacyMap::<u32, u32>,  // validator_id to staked amount
        stake_amount: u32,
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
        self.stake_amount.write(100);
    }

    #[abi(embed_v0)]
    impl ValidatorImpl of super::IValidatorTrait<ContractState> {
        fn stake(ref self: ContractState, amount: u32) -> bool {
            assert!(amount >= self.stake_amount.read(), "Staked amount is less than minimum stake amount");

            let caller = get_caller_address();
            let validator_id = self.total_validators.read();
            let new_validator_id = validator_id + 1;

            let new_validator_info = ValidatorInfo {
                validator_id: new_validator_id,
                stake: amount,
                address: caller,
                status: Status::Active,
                validated_campaigns: Array::new(),
            };

            self.validators.write(new_validator_id, new_validator_info);
            self.validator_stakes.insert(new_validator_id, stake);
            self.total_validators.write(new_validator_id);
            
            Event::Staked(Staked {
                validator_id: validator_id,
                stake: stake,
            });
            true
        }
    }
}