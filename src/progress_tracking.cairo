use starknet::ContractAddress;

#[starknet::interface]
trait IProgressTrackingTrait <TContractState> {
    fn submit_report(ref self: TContractState, campaign_id: u32, report_details: ByteArray, disbursement_amount: u64) -> bool;
    fn get_reports(self: @TContractState, campaign_id: u32) -> Array<ProgressTracking::ProgressReport>;
}

#[starknet::contract]
mod ProgressTracking {
    use starknet::{ContractAddress, get_caller_address};

    #[storage]
    pub struct storage {
        reports: LegacyMap<u32, Array<ProgressReport>>,  // campaign_id to list of progress reports
        tranche: LegacyMap<ContractAddress, u64>,  // Address to tranche amount mapping
    }

    #[derive(Drop, Serde, starknet::Store)]
    pub struct ProgressReport {
        campaign_id: u32,
        report_details: ByteArray,
        timestamp: u64,
        disbursement_amount: u64,
    }
}