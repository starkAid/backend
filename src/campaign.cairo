use starknet::ContractAddress;

#[starknet::interface]
trait IValidator <TContractState> {
    fn is_validator(ref self: TContractState, address: ContractAddress) -> bool;
    fn validate_campaign(ref self: TContractState, campaign_id: u32, validator_address: ContractAddress) -> bool;
    fn get_active_validators_count(self: @TContractState) -> u32;
}

#[starknet::interface]
pub trait ICampaign<TContractState> {
    fn create_campaign(
        ref self: TContractState,
        name: felt252,
        title: felt252,
        campaign_bio_uri: felt252,
        campaign_description_uri: felt252,
        budget_plan_uri: felt252,
        img1_uri: felt252,
        img2_uri: felt252,
        img3_uri: felt252,
        goal: u128,
        location: felt252,
        deadline: u64
    ) -> bool;
    fn vote_on_campaign(ref self: TContractState, campaign_id: u32, approve: bool) -> bool;
    fn disburse_payments(ref self: TContractState, campaign_id: u32) -> bool;
    fn donate(ref self: TContractState, campaign_id: u32, amount: u128, comment_uri: felt252);
    fn get_all_campaigns(self: @TContractState) -> Array<Campaign::CampaignInfo>;
    fn get_campaign(self: @TContractState, campaign_id: u32) -> Campaign::CampaignInfo;
    fn get_campaign_status(self: @TContractState, campaign_id: u32) -> Campaign::CampaignStatus;
    fn goal_not_reached(ref self: TContractState, campaign_id: u32, accept_funds: bool) -> bool;
}

#[starknet::contract]
pub mod Campaign {
    use starknet::{ContractAddress, get_caller_address, get_block_timestamp, contract_address_const, get_contract_address};
    use super::{IValidatorDispatcher, IValidatorDispatcherTrait};
    use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};

    #[storage]
    struct Storage {
        validator_contract_address: ContractAddress,
        amount_donated: LegacyMap<u32, u128>,
        campaigns: LegacyMap<u32, CampaignInfo>,
        donor_count: LegacyMap<u32, u32>,
        comment_uris: LegacyMap<(u32, u32), felt252>, // (campaign_id, donor_id) => comment_uri
        donors: LegacyMap<(u32, u32), ContractAddress>, // (campaign_id, donor_id) => donor_address
        donations: LegacyMap<(u32, ContractAddress), u128>, // (campaign_id, donor_address) => amount
        accept_campaign: LegacyMap<u32, u32>, //campaign_id => votes
        reject_campaign: LegacyMap<u32, u32>,
        campaign_id: u32
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        CampaignCreated: CampaignCreated,
        CampaignVoted: CampaignVoted,
        PaymentDisbursed: PaymentDisbursed,
        DonationMade: DonationMade,
        Transferred: Transferred,
    }

    #[derive(Drop, starknet::Event)]
    pub struct CampaignCreated {
        #[key]
        pub id: u32,
        pub name: felt252,
        pub title: felt252,
        pub goal: u128,
        pub location: felt252,
        pub deadline: u64
    }

    #[derive(Drop, starknet::Event)]
    pub struct CampaignVoted {
        #[key]
        pub campaign_id: u32,
        pub approve: bool,
        pub votes: u32
    }

    #[derive(Drop, starknet::Event)]
    pub struct PaymentDisbursed {
        #[key]
        pub campaign_id: u32,
        pub recipient: ContractAddress,
        pub amount: u128
    }

    #[derive(Drop, starknet::Event)]
    pub struct DonationMade {
        #[key]
        pub campaign_id: u32,
        pub donor: ContractAddress,
        pub amount: u128
    }

    #[derive(Drop, starknet::Event)]
    pub struct Transferred {
        #[key]
        pub sender: ContractAddress,
        pub receiver: ContractAddress,
        pub amount: u128
    }

    #[derive(Copy, Drop, Clone, Serde, PartialEq, starknet::Store)]
    pub enum CampaignStatus {
        Pending,
        Reviewing,
        Approved,
        Rejected,
        Unsuccessful,
        GoalReached
    }

    #[derive(Drop, Serde, starknet::Store)]
    pub struct CampaignInfo {
        id: u32,
        name: felt252,
        title: felt252,
        campaign_bio_uri: felt252,
        campaign_description_uri: felt252,
        budget_plan_uri: felt252,
        img1_uri: felt252,
        img2_uri: felt252,
        img3_uri: felt252,
        goal: u128,
        location: felt252,
        deadline: u64,
        recipient: ContractAddress,
        funds_raised: u128,
        status: CampaignStatus,
        validated: bool,
        payment_disbursed: bool
    }

    #[constructor]
    fn constructor(ref self: ContractState, validator_contract_address: ContractAddress) {
        self.validator_contract_address.write(validator_contract_address);
    }

    #[abi(embed_v0)]
    impl CampaignImpl of super::ICampaign<ContractState> {
        fn create_campaign(
            ref self: ContractState,
            name: felt252,
            title: felt252,
            campaign_bio_uri: felt252,
            campaign_description_uri: felt252,
            budget_plan_uri: felt252,
            img1_uri: felt252,
            img2_uri: felt252,
            img3_uri: felt252,
            goal: u128,
            location: felt252,
            deadline: u64,
        ) -> bool {
            let caller = get_caller_address();
            assert!(!self._is_validator(caller), "Validators cannot create campaigns");

            let id = self.campaign_id.read() + 1;
            let new_campaign = CampaignInfo {
                id,
                name,
                title,
                campaign_bio_uri,
                campaign_description_uri,
                budget_plan_uri,
                img1_uri,
                img2_uri,
                img3_uri,
                goal,
                location,
                deadline,
                recipient: caller,
                funds_raised: 0,
                status: CampaignStatus::Pending,
                validated: false,
                payment_disbursed: false
            };
            self.campaigns.write(id, new_campaign);
            self.campaign_id.write(id);
            self.emit(CampaignCreated {
                id,
                name,
                title,
                goal,
                location,
                deadline
            });
            true
        }

        fn vote_on_campaign(
            ref self: ContractState,
            campaign_id: u32,
            approve: bool
        ) -> bool {
            let timestamp = get_block_timestamp();
            let caller = get_caller_address();
            let validator_address = self.validator_contract_address.read();
            let validatorDispatcher = IValidatorDispatcher { contract_address: validator_address };

            let success = validatorDispatcher.validate_campaign(campaign_id, caller);
            assert(success, 'Validation failed!');

            let mut campaign = self.campaigns.read(campaign_id);
            assert!(campaign.status == CampaignStatus::Pending || campaign.status == CampaignStatus::Reviewing, "Campaign not under review");

            if approve {
                let accepted_votes = self.accept_campaign.read(campaign_id);
                self.accept_campaign.write(campaign_id, accepted_votes + 1);

                if accepted_votes + 1 >= self._get_quorum() * 2 / 3 {
                    campaign.status = CampaignStatus::Approved;
                    campaign.deadline = timestamp + campaign.deadline;
                } else {
                    campaign.status = CampaignStatus::Reviewing;
                }
            } else {
                let rejected_votes = self.reject_campaign.read(campaign_id);
                self.reject_campaign.write(campaign_id, rejected_votes + 1);

                if rejected_votes + 1 >= self._get_quorum() * 2 / 3 {
                    campaign.status = CampaignStatus::Rejected;
                }
            }

            self.campaigns.write(campaign_id, campaign);
            self.emit(CampaignVoted {
                campaign_id,
                approve,
                votes: self.accept_campaign.read(campaign_id)
            });
            true
        }

        fn disburse_payments(
            ref self: ContractState,
            campaign_id: u32
        ) -> bool {
            let mut campaign = self.campaigns.read(campaign_id);
            assert!(campaign.status == CampaignStatus::Approved, "Campaign not approved");
            assert!(campaign.status == CampaignStatus::GoalReached, "Campaign goal not reached");
            assert!(!campaign.payment_disbursed, "Payments already disbursed");

            self._transfer(campaign.recipient, campaign.funds_raised);

            campaign.payment_disbursed = true;
            self.campaigns.write(campaign_id, campaign);

            // redefined due to campaign ownership being transferred already
            let campaign_emit = self.campaigns.read(campaign_id);
            self.emit(PaymentDisbursed {
                campaign_id,
                recipient: campaign_emit.recipient,
                amount: campaign_emit.funds_raised
            });
            
            true
        }

        fn donate(
            ref self: ContractState,
            campaign_id: u32,
            amount: u128,
            comment_uri: felt252
        ) {
            let campaign_contract_address = get_contract_address();
            let donor_address = get_caller_address();
            let mut campaign = self.campaigns.read(campaign_id);
            assert!(get_block_timestamp() < campaign.deadline, "Campaign deadline has passed");
            assert!(campaign.status == CampaignStatus::Approved, "Campaign not approved");
            assert!(campaign.status != CampaignStatus::GoalReached, "Campaign goal already reached");

            self._transfer_from(donor_address, campaign_contract_address, amount);

            if campaign.funds_raised >= campaign.goal {
                campaign.status = CampaignStatus::GoalReached;
                self.disburse_payments(campaign_id);
            }
            campaign.funds_raised += amount;
            self.campaigns.write(campaign_id, campaign);

            let donor_id = self.donor_count.read(campaign_id) + 1;
            self.donors.write((campaign_id, donor_id), donor_address);
            self.comment_uris.write((campaign_id, donor_id), comment_uri);
            self.donor_count.write(campaign_id, donor_id);

            self.donations.write((campaign_id, donor_address), amount);
            self.amount_donated.write(campaign_id, self.amount_donated.read(campaign_id) + amount);

            self.emit(DonationMade {
                campaign_id,
                donor: donor_address,
                amount
            });
        }

        fn goal_not_reached(
            ref self: ContractState,
            campaign_id: u32,
            accept_funds: bool
        ) -> bool {
            let mut campaign = self.campaigns.read(campaign_id);
            assert!(campaign.status == CampaignStatus::Approved, "Campaign is not approved");
            assert!(get_block_timestamp() >= campaign.deadline, "Campaign deadline has not passed yet");

            if accept_funds {
                campaign.status = CampaignStatus::Unsuccessful;
                let recipient = campaign.recipient;
                self._transfer(recipient, campaign.funds_raised);
                self.emit(PaymentDisbursed {
                    campaign_id,
                    recipient,
                    amount: campaign.funds_raised
                });
            } else {
                self._refund_donors(campaign_id);
                campaign.status = CampaignStatus::Rejected;
            }
            self.campaigns.write(campaign_id, campaign);
            true
        }

        fn get_all_campaigns(self: @ContractState) -> Array<CampaignInfo> {
            let mut campaigns = ArrayTrait::new();
            let mut i = 1;
            let count = self.campaign_id.read();

            while i <= count {
                let campaign = self.campaigns.read(i);
                campaigns.append(campaign);

                i += 1;
            };
            
            campaigns
        }

        fn get_campaign(self: @ContractState, campaign_id: u32) -> CampaignInfo {
            self.campaigns.read(campaign_id)
        }

        fn get_campaign_status(self: @ContractState, campaign_id: u32) -> CampaignStatus {
            self.campaigns.read(campaign_id).status
        }
    }

    #[generate_trait]
    impl ERC20Impl of ERC20Trait {
        fn _transfer_from(ref self: ContractState, sender: ContractAddress, recipient: ContractAddress, amount: u128) {
            let eth_dispatcher = IERC20Dispatcher {
                contract_address: contract_address_const::<0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d>() // STRK token Contract Address
            };
            assert(eth_dispatcher.balance_of(sender) >= amount.into(), 'insufficient funds');

            // eth_dispatcher.approve(validator_contract_address, amount.into()); This is wrong as it is the validator contract trying to approve itself
            let success = eth_dispatcher.transfer_from(sender, recipient, amount.into());
            assert(success, 'ERC20 transfer_from fail!');
        }

        fn _transfer(ref self: ContractState, recipient: ContractAddress, amount: u128) {
            let eth_dispatcher = IERC20Dispatcher {
                contract_address: contract_address_const::<0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d>() // STRK token Contract Address
            };
            let success = eth_dispatcher.transfer(recipient, amount.into());
            assert(success, 'ERC20 transfer fail!');
        }
    }

    #[generate_trait]
    impl ValidatorImpl of ValidatorTrait {
        fn _is_validator(ref self: ContractState, address: ContractAddress) -> bool {
            let caller = get_caller_address();
            let validator_address = self.validator_contract_address.read();
            let validatorDispatcher = IValidatorDispatcher { contract_address: validator_address };

            validatorDispatcher.is_validator(caller)
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn _get_quorum(self: @ContractState) -> u32 {
            let validator_address = self.validator_contract_address.read();
            let validatorDispatcher = IValidatorDispatcher { contract_address: validator_address };

            validatorDispatcher.get_active_validators_count()
        }

        fn _refund_donors(ref self: ContractState, campaign_id: u32) {
            let mut i = 1;
            let count = self.donor_count.read(campaign_id);
            while i <= count {
                let donor_address = self.donors.read((campaign_id, i));
                let amount = self.donations.read((campaign_id, donor_address));
                self._transfer(donor_address, amount);

                self.amount_donated.write(campaign_id, self.amount_donated.read(campaign_id) - amount);

                i += 1;
            }
        }
    }
}