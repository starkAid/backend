use starknet::ContractAddress;

#[starknet::interface]
pub trait IAuth<TContractState> {

    fn register_user(ref self: TContractState, name: felt252);
    fn get_user(self: @TContractState, index: u64) -> Auth::User;    
    fn get_all_users(self: @TContractState) -> Array<Auth::User>;
    fn update_user_name(ref self: TContractState, newUsername: felt252) -> bool;    
}

#[starknet::contract]
mod Auth {
    use starknet::{ContractAddress, get_caller_address, contract_address_const};

    #[storage]
    struct Storage {        
       name: felt252,
       address: ContractAddress,
       owner: ContractAddress,
       addressToUser: LegacyMap<ContractAddress, User>,
       addressToName: LegacyMap<ContractAddress, felt252>,
       nameToAddress: LegacyMap<felt252, ContractAddress>,
       allUsers: LegacyMap::<u64, User>,
       userId: u64
    }  
    

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        RegistrationSuccessiful: RegistrationSuccessiful,        
    }

    #[derive(Drop, starknet::Event)]
    pub struct RegistrationSuccessiful {        
        pub userAddress: ContractAddress,
        #[key]
        pub userName: felt252,
    }
   
    #[derive(Drop, Serde, starknet::Store)]
    pub struct User {
        id: u64,
        name: felt252,
        address: ContractAddress,
    } 
  

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress) {
        self.owner.write(owner);
    }

    #[abi(embed_v0)]
    impl AuthImpl of super::IAuth<ContractState> {
        fn register_user(ref self: ContractState, name: felt252) {

            let id = self.userId.read();
            let currentId = id + 1;
            let userAddress = get_caller_address();            
            self._register_user(currentId, name, userAddress);   
            self.userId.write(currentId);

            self.emit(RegistrationSuccessiful{userAddress: userAddress, userName: name})
        }

        fn update_user_name(ref self: ContractState, newUsername: felt252) -> bool{
            let msg_sender = get_caller_address();
            let currentUser = self.addressToUser.read(msg_sender);
            self._register_user(currentUser.id, newUsername, msg_sender);
            true
        }

        fn get_user(self: @ContractState, index: u64) -> User{
            self.allUsers.read(index)
        }

        fn get_all_users(self: @ContractState) -> Array<User>{
            let mut users = ArrayTrait::new();
            let mut count: u64 = self.userId.read();
            let mut index: u64 = 1;

            while index < count
                + 1 {
                    let readUser = self.allUsers.read(index);
                    users.append(readUser);
                    index += 1;
                };

            users
        }       
    }

    #[generate_trait]
    impl PrivateImpl of PrivateTrait {
        fn _register_user(ref self: ContractState, currentId: u64, name: felt252, address: ContractAddress) {

            let existing_name = self.nameToAddress.read(name);
            let addressZero: ContractAddress = contract_address_const::<0>();
            assert(existing_name == addressZero, 'Name already taken');           
            let user = User{id: currentId, name: name, address:address};
            self.allUsers.write(currentId, user);
        }
    }
}