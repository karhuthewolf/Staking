use starknet::ContractAddress;

#[abi]
trait IERC721 {
    fn approve(to: ContractAddress, tokenId: u256);
}

#[contract]
mod NftLocker {
    use starknet::get_caller_address;
    use starknet::ContractAddress;
    use super::IERC721Dispatcher;
    use super::IERC721DispatcherTrait;

    #[storage]
    struct Storage {
        _nftAdrs: ContractAddress,
        _locker: ContractAddress,
        _owner: ContractAddress,
    }

    #[constructor]
    fn constructor(
        nftAdrs: ContractAddress, locker: ContractAddress, owner: ContractAddress
    ) {
        _nftAdrs::write(nftAdrs);
        _locker::write(locker);
        _owner::write(owner);
    }

    #[external]
    fn approveLocker(tokenId: u256) {
        let caller = get_caller_address();
        assert(caller == _locker::read(), 'Only locker function');
        let nftAdrs = _nftAdrs::read();
        let nftDispatcher = IERC721Dispatcher { contract_address: nftAdrs };
        nftDispatcher.approve(_locker::read(), tokenId);
    }

    #[external]
    fn approveOwner(tokenId: u256){
        let caller = get_caller_address();
        assert(caller == _owner::read(), 'Only owner function');
        let nftAdrs = _nftAdrs::read();
        let nftDispatcher = IERC721Dispatcher { contract_address: nftAdrs };
        nftDispatcher.approve(_owner::read(), tokenId);
    }
}