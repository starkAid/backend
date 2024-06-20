use starknet::ContractAddress;

#[starknet::interface]
pub trait IAuth<TContractState> {
    fn createAccount(ref self: TContractState, name: felt252);

    fn getUserInfo(ref self: TContractState, user: ContractAddress) -> User;

    fn getUserInfo(ref self: TContractState, user: Name) -> User;

    fn usernameExists(self: @TContractState, user: Name) -> bool;

    fn nameFromAddress(self: @TContractState, user: ContractAddress) -> felt252;

    fn addressFromName(self: @TContractState, user: felt252) -> ContractAddress;

    fn getAllUsers(self: @TContractState) -> Array<User>;
   
}