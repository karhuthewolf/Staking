

mod ERC721 {
    use starknet::ContractAddress;
    

    struct Storage {
        fundsRecipient: felt252,
        maxSupply: u256,
        counteur: u256,
        royalties: u256,
    }
}