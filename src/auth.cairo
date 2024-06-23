use starknet::ContractAddress;

#[starknet::interface]
pub trait IAuth<TContractState> {
    fn register_user(ref self: TContractState, username: felt252);
    fn get_user(self: @TContractState, index: u32) -> Auth::User;    
    fn get_all_users(self: @TContractState) -> Array<Auth::User>;
    fn update_username(ref self: TContractState, newUsername: felt252) -> bool;
    fn get_user_id(self: @TContractState, address: ContractAddress) -> u32;
}

#[starknet::contract]
mod Auth {
    use starknet::{ContractAddress, get_caller_address, contract_address_const};

    #[storage]
    struct Storage {
       users: LegacyMap::<u32, User>,  // user_id to User
       total_users: u32
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
            let caller = get_caller_address();
            assert(!self._returning_user(caller), 'User already exists');

            let id = self.total_users.read();
            let currentId = id + 1;

            self._register_user(currentId, username, caller);   
            self.total_users.write(currentId);

            // let e_user = self.users.read(currentId);
            self.emit(RegistrationSuccessiful{userAddress: caller, userName: username})
        }

        fn update_username(ref self: ContractState, newUsername: felt252) -> bool{
            let caller = get_caller_address();
            assert(self._returning_user(caller), 'User does not exist');
            let user_id = self.get_user_id(caller);

            self._register_user(user_id, newUsername, caller);
            true
        }

        fn get_user(self: @ContractState, index: u32) -> User {
            self.users.read(index)
        }

        fn get_all_users(self: @ContractState) -> Array<User>{
            let mut users = ArrayTrait::new();
            let mut count: u32 = self.total_users.read();
            let mut index: u32 = 1;

            while index < count
                + 1 {
                    let readUser = self.users.read(index);
                    users.append(readUser);
                    index += 1;
                };

            users
        }

        fn get_user_id(self: @ContractState, address: ContractAddress) -> u32 {
            let mut user_id = 0;
            let mut count = self.total_users.read();

            while count > 0 {
                let user = self.users.read(count);

                if user.address == address {
                    user_id = user.id;
                    break;
                }

                count -= 1;
            };

            user_id
        }
    }

    #[generate_trait]
    impl PrivateImpl of PrivateTrait {
        fn _register_user(ref self: ContractState, currentId: u32, username: felt252, address: ContractAddress) {
            let user = User{id: currentId, username: username, address:address};
            self.users.write(currentId, user);
        }

        fn _returning_user(self: @ContractState, user_address: ContractAddress) -> bool {
            let user_id = self.get_user_id(user_address);

            user_id != 0
        }
    }
}