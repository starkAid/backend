use starknet::ContractAddress;

#[starknet::interface]
trait IValidator <TContractState> {
    fn get_validator_id(self: @TContractState, address: ContractAddress) -> u32;
    fn is_validator(self: @TContractState, address: ContractAddress) -> bool;
}

#[starknet::interface]
trait IValidatorReport<TContractState> {
    fn submit_report(ref self: TContractState, campaign_id: u32, response_given: bool, report_uri: felt252) -> bool;
    fn get_report(self: @TContractState, campaign_id: u32, report_id: u32) -> ValidatorReport::CampaignReport;
    fn get_campaign_reports(self: @TContractState, campaign_id: u32) -> Array<ValidatorReport::CampaignReport>;
}

#[starknet::contract]
mod ValidatorReport {
    use starknet::{ContractAddress, get_caller_address, get_block_timestamp};
    use super::{IValidatorDispatcher, IValidatorDispatcherTrait};

    #[storage]
    struct Storage {
        validator_contract_address: ContractAddress,
        report_count: u32,
        campaign_report: LegacyMap<(u32, u32), CampaignReport>, // (campaign_id, report_count) -> CampaignReport
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
        pub report_id: u32,
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
    impl ValidatorReportImpl of super::IValidatorReport<ContractState> {
        fn submit_report(ref self: ContractState, campaign_id: u32, response_given: bool, report_uri: felt252) -> bool {
            let caller = get_caller_address();
            let timestamp = get_block_timestamp();
            let count = self.report_count.read() + 1;

            let validator_id = self._get_validator_id(caller);

            assert!(self._is_validator(caller), "Not a validator");
            assert!(!self.campaign_report_submitted.read((campaign_id, validator_id)), "Report already submitted for this campaign");

            let report = CampaignReport {
                report_id: count,
                campaign_id: campaign_id,
                validator_id: validator_id,
                timestamp: timestamp,
                response_given: response_given,
                report_uri: report_uri,
            };
            self.campaign_report.write((campaign_id, count), report);
            self.report_count.write(count);
            self.campaign_report_submitted.write((campaign_id, validator_id), true);

            self.emit(ReportSubmitted { campaign_id, timestamp });
            true
        }

        fn get_report(self: @ContractState, campaign_id: u32, report_id: u32) -> CampaignReport {
            self.campaign_report.read((campaign_id, report_id))
        }

        fn get_campaign_reports(self: @ContractState, campaign_id: u32) -> Array<CampaignReport> {
            let mut reports = ArrayTrait::new();
            let mut i = 1;
            let count = self.report_count.read();

            while i <= count {
                let report = self.campaign_report.read((campaign_id, i));
                reports.append(report);

                i += 1;
            };
            
            reports
        }
    }

    #[generate_trait]
    impl ValidatorImpl of ValidatorTrait {
        fn _is_validator(ref self: ContractState, address: ContractAddress) -> bool {
            let validator_address = self.validator_contract_address.read();
            let validatorDispatcher = IValidatorDispatcher { contract_address: validator_address };

            validatorDispatcher.is_validator(address)
        }

        fn _get_validator_id(ref self: ContractState, address: ContractAddress) -> u32 {
            let validator_address = self.validator_contract_address.read();
            let validatorDispatcher = IValidatorDispatcher { contract_address: validator_address };

            validatorDispatcher.get_validator_id(address)
        }
    }
}