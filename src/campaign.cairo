use starknet::ContractAddress;

#[starknet::interface]
pub trait IS<TContractState> {
    fn createProject(ref self: TContractState, title: felt252, description: felt252, goal: u256, deadline: u64, receipient: ContractAddress) -> bool;  

    // fn endProject(ref self: TContractState, index: u32) -> bool;

    fn contribute(ref self: TContractState, index: u32, amount: u256, comment: felt252) ;

    fn allProjects(self: @TContractState) -> Array<StarkAid::Project>;  
}


#[starknet::contract]
pub mod StarkAid {
    use starknet::{ContractAddress, get_caller_address, get_block_timestamp, contract_address_const};

    #[storage]
    struct Storage {        
        owner: ContractAddress,
        balances: LegacyMap<ContractAddress, u256>,
        projects: LegacyMap::<u32, Project>,
        comments: LegacyMap::<u32, Array<felt252>>,      //mapping of comments to user address to project id
        donors: LegacyMap::<u32, Array<ContractAddress>>,
        projectId: u32
    }

        
    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Transferred: Transferred,
        // ContributionMade: ContributionMade,
    }

    #[derive(Drop, starknet::Event)]
    struct Transferred {
        sender: ContractAddress,
        receiver: ContractAddress,
        amount: u256
    }

    #[derive(Drop, starknet::Event)]
    // struct ContributionMade {
    //     sender: ContractAddress,
    //     Project: u32,
    //     amount: u256
    // }

    #[derive(Drop, Serde, starknet::Store)]
    pub struct Project {
        id: u32,
        title: felt252,
        description: felt252,
        deadline: u64,     
        goal: u256,
        receipient: ContractAddress,
        fundsRaised: u256,
        validated: bool,
        paymentDisbursed: bool,
        comment: felt252
    }

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress) {
        self.owner.write(owner);
    }

    #[abi(embed_v0)]
    impl StarkAidImpl of super::IStarkAid<ContractState> {
        fn createProject(ref self: ContractState, title: felt252, description: felt252, goal: u256, deadline: u64, receipient: ContractAddress) -> bool {
            let id = self.projectId.read();
            let currentId = id + 1;
            self._createProject(currentId, title, description, goal, deadline, receipient);
            self.projectId.write(currentId);
            true
        }
        
        fn contribute(ref self: ContractState, index: u32, amount: u256, comment: felt252) {
            let donor_address = get_caller_address();  // Get caller's address
            let mut project = self.projects.read(index);            
            assert(get_block_timestamp() < project.deadline, 'Project deadline has passed.');

            assert(project.fundsRaised >= project.goal, 'Funding goal not reached.');

            let user_balance = self.balances.read(donor_address);       

           

            assert(user_balance > amount, 'Insufficient funds');
            let owner = self.owner.read();

            self._transfer(owner, amount);

            project.fundsRaised += amount;
            self.projects.write(index, project);

            let mut comments = self.comments.read(index);
            comments.append(comment);
            self.comments.write(index, comments);

            // Add to donor list
            let mut donors = self.donors.read(index);        
                donors.append(donor_address);
                self.donors.write(index, donors);
            }       
                
        } 
        
        fn allProjects(self: @ContractState) -> Array<Project> {
            let mut totalProjects = ArrayTrait::new();  // Ensure ArrayTrait is correctly implemented or use a standard method if available
            let mut count = self.projectId.read();        
            let mut index: u32 = 1;                   
        
            while index <= count {
                let oneProject = self.projects.read(index);  
                totalProjects.append(oneProject);              
                index += 1;  
                                         
            };       
    
        }
        
        fn disbursePayments(ref self: ContractState, index: u32) -> bool {
            let mut project = self.projects.read(index);
            assert(project.fundsRaised >= project.goal, 'Funding goal not reached.');
            
            assert(!project.paymentDisbursed, 'Payments already disbursed.');

            let recieverAddress = project.receipient;

            let addressZero: ContractAddress = contract_address_const::<0>();

            assert!(recieverAddress != addressZero);            
        
            self._transfer(project.receipient, project.fundsRaised);

            let mut currentProject = self.projects.read(index);

            currentProject.paymentDisbursed == true;           

            self.projects.write(index, project);

            true
        }

          

     #[generate_trait]
     impl internalfunctionsImpl of internalfunctionsTrait {
        fn _createProject(ref self: ContractState, currentId: u32, title: felt252, description: felt252, goal: u256, deadline: u64, receipient: ContractAddress) {
            let mut project = Project{id: currentId, title: title, description: description,goal: goal, deadline: deadline, receipient: receipient, fundsRaised: 0, validated: false, paymentDisbursed: false, comment: 'project start'};
            self.projects.write(currentId, project);
        }

        fn _transfer(ref self: ContractState, receiver: ContractAddress, amount: u256){
            let sender = self.owner.read();
            let caller:ContractAddress = get_caller_address();
        
            assert(caller == sender, 'Not owner');
            self.balances.write(receiver, self.balances.read(receiver) + amount);
            self.balances.write(caller, self.balances.read(caller) - amount);   
            self.emit(Transferred {sender,receiver, amount});     
        }

    }
}