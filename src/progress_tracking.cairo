use starknet::ContractAddress;

#[starknet::interface]
pub trait ICampaign<TContractState> {
    fn is_beneficiary(ref self: TContractState, campaign_id: u32, address: ContractAddress) -> bool;
}

#[starknet::interface]
trait IProgressTracking <TContractState> {
    fn submit_report(ref self: TContractState, campaign_id: u32, disbursed_amount: u64, report_uri: felt252) -> bool;
    fn get_campaign_report(self: @TContractState, campaign_id: u32) -> ProgressTracking::ProgressReport;
    fn get_reports(self: @TContractState) -> Array<ProgressTracking::ProgressReport>;
}

#[starknet::contract]
mod ProgressTracking {
    use starknet::{ContractAddress, get_caller_address, get_block_timestamp};
    use super::{ICampaignDispatcher, ICampaignDispatcherTrait};

    #[storage]
    struct Storage {
        campaign_contract_address: ContractAddress,
        report_count: u32,
        campaign_report: LegacyMap<u32, ProgressReport>, // ReportId -> ProgressReport
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
        pub report_id: u32,
        pub campaign_id: u32,
        pub campaign_owner: ContractAddress,
        pub timestamp: u64,
        pub disbursed_amount: u64,
        pub report_uri: felt252,
    }

    #[constructor]
    fn constructor(ref self: ContractState, campaign_contract_address: ContractAddress) {
        self.campaign_contract_address.write(campaign_contract_address);
    }

    #[abi(embed_v0)]
    impl ProgressTrackingImpl of super::IProgressTracking<ContractState> {
        fn submit_report(ref self: ContractState, campaign_id: u32, disbursed_amount: u64, report_uri: felt252) -> bool {
            let caller = get_caller_address();
            let count = self.report_count.read() + 1;

            assert!(self._is_beneficiary(campaign_id, caller), "Only beneficiary can submit report");
            assert!(!self.campaign_report_submitted.read((campaign_id, caller)), "Report already submitted for this campaign");

            let timestamp = get_block_timestamp();
            let report = ProgressReport {
                report_id: count,
                campaign_id: campaign_id,
                campaign_owner: caller,
                timestamp: timestamp,
                disbursed_amount: disbursed_amount,
                report_uri: report_uri,
            };
            self.campaign_report.write(count, report);
            self.report_count.write(count);
            self.campaign_report_submitted.write((campaign_id, caller), true);

            self.emit(ReportSubmitted { campaign_id, timestamp });
            true
        }

        fn get_campaign_report(self: @ContractState, campaign_id: u32) -> ProgressReport {
            self.campaign_report.read(campaign_id)
        }

        fn get_reports(self: @ContractState) -> Array<ProgressReport> {
            let mut reports = ArrayTrait::new();
            let mut i = 1;
            let count = self.report_count.read();

            while i <= count {
                let report = self.campaign_report.read(i);
                reports.append(report);

                i += 1;
            };
            
            reports
        }
    }

    #[generate_trait]
    impl CampaignImpl of CampaignTrait {
        fn _is_beneficiary(ref self: ContractState, campaign_id: u32, address: ContractAddress) -> bool {
            let campaign_address = self.campaign_contract_address.read();
            let campaignDispatcher = ICampaignDispatcher { contract_address: campaign_address };

            campaignDispatcher.is_beneficiary(campaign_id, address)
        }
    }
}