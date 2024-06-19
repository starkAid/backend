use starknet::ContractAddress;

#[starknet::interface]
trait IProgressTrackingTrait <TContractState> {
    fn submit_report(ref self: TContractState, campaign_id: u32, report_details: ByteArray, disbursed_amount: u64) -> bool;
    fn get_reports(self: @TContractState, campaign_id: u32) -> Array<ProgressTracking::ProgressReport>;
}

#[starknet::contract]
mod ProgressTracking {
    use starknet::{ContractAddress, get_caller_address, get_block_timestamp};

    #[storage]
    pub struct storage {
        reports: LegacyMap<u32, Array<ProgressReport>>,  // campaign_id to list of progress reports
    }

     #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        ReportSubmitted: ReportSubmitted,
    }

    #[derive(Drop, starknet::Event)]
    pub struct ReportSubmitted {
        #[key]
        campaign_id: u32,
        timestamp: u64,
        disbursed_amount: u64,
    }

    #[derive(Drop, Serde, starknet::Store)]
    pub struct ProgressReport {
        campaign_id: u32,
        report_details: ByteArray,
        timestamp: u64,
        disbursed_amount: u64,
    }

    #[constructor]
    fn constructor(ref self: ContractState) {
        reports: LegacyMap::new(),
    }

    #[abi(embed_v0)]
    impl ProgressTrackingImpl of super::IProgressTrackingTrait<ContractState> {
        fn submit_report(ref self: ContractState, campaign_id: u32, report_details: ByteArray, disbursed_amount: u64) -> bool {
            let caller = get_caller_address();
            let report = ProgressReport {
                campaign_id: campaign_id,
                report_details: report_details,
                timestamp: env::block_timestamp(),
                disbursed_amount: disbursed_amount,
            };
            self.storage.reports.insert(campaign_id, report);
            Event::ReportSubmitted(ReportSubmitted {
                campaign_id: campaign_id,
                timestamp: env::block_timestamp(),
                disbursed_amount: disbursed_amount,
            });
            true
        }

        fn get_reports(self: @ContractState, campaign_id: u32) -> Array<ProgressReport> {
            self.storage.reports.get(campaign_id).unwrap_or_default()
        }
    }
}