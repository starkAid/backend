use starknet::ContractAddress;

#[starknet::interface]
pub trait IAuth<TContractState> {
    fn register_user(ref self: TContractState, username: felt252);
    fn get_user(self: @TContractState, index: u32) -> Auth::User;    
    fn get_all_users(self: @TContractState) -> Array<Auth::User>;
    fn update_username(ref self: TContractState, newUsername: felt252) -> bool;
    fn is_authenticated(self: @TContractState, user_address: ContractAddress) -> bool;
}

#[starknet::contract]
mod Auth {
    use starknet::{ContractAddress, get_caller_address, contract_address_const};

    #[storage]
    struct Storage {
       address_to_userId: LegacyMap<ContractAddress, u32>,
       allUsers: LegacyMap::<u32, User>,
       userId: u32
    }  
    

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        RegistrationSuccessiful: RegistrationSuccessiful,        
    }

    #[derive(Drop, starknet::Event)]
    pub struct RegistrationSuccessiful {
        #[key]     
        pub userAddress: ContractAddress,
        #[key]
        pub userName: felt252,
    }
   
    #[derive(Drop, Serde, starknet::Store)]
    pub struct User {
        id: u32,
        username: felt252,
        address: ContractAddress,
    } 
  

    #[constructor]
    fn constructor(ref self: ContractState) {}

    #[abi(embed_v0)]
    impl AuthImpl of super::IAuth<ContractState> {
        fn register_user(ref self: ContractState, username: felt252) {
            let id = self.userId.read();
            let currentId = id + 1;
            let userAddress = get_caller_address();

            self._register_user(currentId, username, userAddress);   
            self.userId.write(currentId);
            self.address_to_userId.write(userAddress, currentId);

            let e_user = self.allUsers.read(currentId);
            self.emit(RegistrationSuccessiful{userAddress: e_user.address, userName: e_user.username})
        }

        fn update_username(ref self: ContractState, newUsername: felt252) -> bool{
            let caller = get_caller_address();
            let user_id = self._get_user_id(caller);

            self._register_user(user_id, newUsername, caller);
            true
        }

        fn get_user(self: @ContractState, index: u32) -> User {
            self.allUsers.read(index)
        }

        fn get_all_users(self: @ContractState) -> Array<User>{
            let mut users = ArrayTrait::new();
            let mut count: u32 = self.userId.read();
            let mut index: u32 = 1;

            while index < count
                + 1 {
                    let readUser = self.allUsers.read(index);
                    users.append(readUser);
                    index += 1;
                };

            users
        }

        fn is_authenticated(self: @ContractState, user_address: ContractAddress) -> bool {
            let user_id = self._get_user_id(user_address);

            user_id != 0
        }
    }

    #[generate_trait]
    impl PrivateImpl of PrivateTrait {
        fn _register_user(ref self: ContractState, currentId: u32, username: felt252, address: ContractAddress) {
            let user_clone = self.allUsers.read(currentId);
            let existing_address = user_clone.address;
            let addressZero: ContractAddress = contract_address_const::<0>();
            assert(existing_address == addressZero, 'Name already taken');

            let user = User{id: currentId, username: username, address:address};
            self.allUsers.write(currentId, user);
        }

        fn _get_user_id(self: @ContractState, user_address: ContractAddress) -> u32 {
            let userId = self.address_to_userId.read(user_address);
            assert(userId != 0, 'User not found');

            userId
        }
    }
}