use starknet::ContractAddress;

// #[starknet::interface]
// trait IValidatorTrait <TContractState> {
//     fn get_validator_id(self: @TContractState, address: ContractAddress) -> u32;
// }

#[starknet::interface]
trait IProgressTracking <TContractState> {
    fn submit_report(ref self: TContractState, campaign_id: u32, disbursed_amount: u64, report_uri: felt252) -> bool;
    fn get_campaign_report(self: @TContractState, campaign_id: u32) -> ProgressTracking::ProgressReport;
    // fn get_validator_report(self: @TContractState, campaign_id: u32, validator_id: u32) -> ProgressReport;
    // fn get_reports(self: @TContractState) -> Array<ProgressTracking::ProgressReport>; I need to get all campaign_ids to get all reports
}

#[starknet::contract]
mod ProgressTracking {
    use starknet::{ContractAddress, get_caller_address, get_block_timestamp};

    #[storage]
    struct Storage {
        campaign_report: LegacyMap<u32, ProgressReport>, // CampaignId -> ProgressReport
        campaign_report_submitted: LegacyMap::<(u32, ContractAddress), bool>, //(campaign_id, campaign_owner addr) -> bool
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
    pub struct ProgressReport {
        pub campaign_id: u32,
        pub campaign_owner: ContractAddress,
        pub timestamp: u64,
        pub disbursed_amount: u64,
        pub report_uri: felt252,
    }

    #[constructor]
    fn constructor(ref self: ContractState) {}

    #[abi(embed_v0)]
    impl ProgressTrackingImpl of super::IProgressTracking<ContractState> {
        fn submit_report(ref self: ContractState, campaign_id: u32, disbursed_amount: u64, report_uri: felt252) -> bool {
            let caller = get_caller_address();

            assert!(!self.campaign_report_submitted.read((campaign_id, caller)), "Report already submitted for this campaign");

            let timestamp = get_block_timestamp();
            let report = ProgressReport {
                campaign_id: campaign_id,
                campaign_owner: caller,
                timestamp: timestamp,
                disbursed_amount: disbursed_amount,
                report_uri: report_uri,
            };
            self.campaign_report.write(campaign_id, report);
            self.campaign_report_submitted.write((campaign_id, caller), true);

            self.emit(ReportSubmitted { campaign_id, timestamp });
            true
        }

        fn get_campaign_report(self: @ContractState, campaign_id: u32) -> ProgressReport {
            self.campaign_report.read(campaign_id)
        }
    }
}