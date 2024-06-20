use starknet::ContractAddress;

#[starknet::interface]
trait IValidator <TContractState> {
    fn get_validator_id(self: @TContractState, address: ContractAddress) -> u32;
}

#[starknet::interface]
trait IProgressTrackingTrait <TContractState> {
    fn submit_report(ref self: TContractState, campaign_id: u32, response_given: bool, report_uri: felt252) -> bool;
    fn get_campaign_report(self: @TContractState, campaign_id: u32) -> ValidatorReport::CampaignReport;
    // fn get_reports(self: @TContractState) -> Array<ProgressTracking::ProgressReport>; I need to get all campaign_ids to get all reports
}

#[starknet::contract]
mod ValidatorReport {
    use starknet::{ContractAddress, get_caller_address, get_block_timestamp};
    use super::{IValidatorDispatcher, IValidatorDispatcherTrait};

    #[storage]
    struct Storage {
        validator_contract_address: ContractAddress,
        campaign_report: LegacyMap<(u32, u32), CampaignReport>, // (campaign_id, validator_id) -> CampaignReport
        campaign_report_submitted: LegacyMap::<(u32, u32), bool>, //(campaign_id, validator_id) -> bool
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        ReportSubmitted: ReportSubmitted,
    }

    #[derive(Drop, starknet::Event)]
    pub struct ReportSubmitted {
        #[key]
        pub campaign_id: u32,
        pub timestamp: u64,
    }

    #[derive(Drop, Serde, starknet::Store)]
    pub struct CampaignReport {
        pub campaign_id: u32,
        pub validator_id: u32,
        pub timestamp: u64,
        pub response_given: bool,
        pub report_uri: felt252,
    }

    #[constructor]
    fn constructor(ref self: ContractState, validator_contract_address: ContractAddress) {
        self.validator_contract_address.write(validator_contract_address);
    }

    #[abi(embed_v0)]
    impl ProgressTrackingImpl of super::IProgressTrackingTrait<ContractState> {
        fn submit_report(ref self: ContractState, campaign_id: u32, response_given: bool, report_uri: felt252) -> bool {
            let caller = get_caller_address();
            let validator_address = self.validator_contract_address.read();
            let validatorDispatcher = IValidatorDispatcher { contract_address: validator_address };
            let validator_id = validatorDispatcher.get_validator_id(caller);
            let timestamp = get_block_timestamp();

            assert!(!self.campaign_report_submitted.read((campaign_id, validator_id)), "Report already submitted for this campaign");

            let report = CampaignReport {
                campaign_id: campaign_id,
                validator_id: validator_id,
                timestamp: timestamp,
                response_given: response_given,
                report_uri: report_uri,
            };
            self.campaign_report.write((campaign_id, validator_id), report);
            self.campaign_report_submitted.write((campaign_id, validator_id), true);

            self.emit(ReportSubmitted { campaign_id, timestamp });
            true
        }

        fn get_campaign_report(self: @ContractState, campaign_id: u32) -> CampaignReport {
            let caller = get_caller_address();
            let validator_address = self.validator_contract_address.read();
            let validatorDispatcher = IValidatorDispatcher { contract_address: validator_address };
            let validator_id = validatorDispatcher.get_validator_id(caller);

            self.campaign_report.read((campaign_id, validator_id))
        }
    }
}