use starknet::ContractAddress;

#[starknet::interface]
trait IValidatorTrait <TContractState> {
    fn stake(ref self: TContractState) -> bool;
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
}