use starknet::ContractAddress;
use box::BoxTrait;

#[abi]
trait IERC721 {
    fn transferFrom(from_: ContractAddress, to: ContractAddress, tokenId: u256);
    fn ownerOf(tokenId: u256) -> ContractAddress;
}

#[abi]
trait IERC20 {
    fn mint(recipient: ContractAddress, amount: u256);
}

#[abi]
trait ISafe {
    fn approveLocker(tokenId: u256);
}

fn get_block_timestamp() -> u64 {
    let info = starknet::get_block_info().unbox();
    return info.block_timestamp;
}

fn as_u256(high: u128, low: u128) -> u256 {
    u256 { low, high }
}


#[contract]
mod Locker {
    use starknet::get_caller_address;
    use starknet::ContractAddress;
    use starknet::contract_address::ContractAddressIntoFelt252;
    use super::IERC721Dispatcher;
    use super::IERC721DispatcherTrait;
    use super::IERC20Dispatcher;
    use super::IERC20DispatcherTrait;
    use super::ISafeDispatcher;
    use super::ISafeDispatcherTrait;
    use super::get_block_timestamp;
    use super::as_u256;
    use starknet::Into;
    use starknet::TryInto;
    use starknet::syscalls::deploy_syscall;
    use starknet::class_hash::ClassHash;
    use starknet::SyscallResult;
    use option::OptionTrait;
    use array::ArrayTrait;
    use array::SpanTrait;

    struct Storage {
        _timeframeById: LegacyMap::<u16, u64>, // timeframeId => timeframe
        _timeframeIdByTokenId: LegacyMap::<u256, u16>, // tokenId => timeframeId
        _tokensAmountByTimeframeId: LegacyMap::<u16, u256>, // timeframeId => amount per second
        
        _isLockedTokenId: LegacyMap::<u256, bool>, // tokenId => isLocked
        _safeAdrsByTokenId: LegacyMap::<u256, ContractAddress>, // tokenId => safeAdrs
        _safeByAdrs: LegacyMap::<ContractAddress, ContractAddress>, // ownerAdrs => safeAdrs
        _ownerOfSafe: LegacyMap::<ContractAddress, ContractAddress>, // safeAdrs => ownerAdrs
        _timestampLocked: LegacyMap::<u256, u64>, // tokenId => timestamp
        _lastHarvest: LegacyMap::<u256, u64>, // tokenId => timestamp

        _nftAdrs: ContractAddress, // wolves nfts
        _tokenAdrs: ContractAddress, // meat token
        _owner: ContractAddress, // owner of the contract
        _lockerSelfAdrs: ContractAddress, // locker contract address
        _safeClassHash: ClassHash, // safe classhash to deploy contract
    }

    #[constructor]
    fn constructor(
        nftAdrs: ContractAddress,
        tokenAdrs: ContractAddress,
        owner: ContractAddress,
        safeClassHash: ClassHash,
    ) {
        _timeframeById::write(0_u16, 1314000_u64);
        _timeframeById::write(1_u16, 2628000_u64);
        _timeframeById::write(2_u16, 5256000_u64);
        _timeframeById::write(3_u16, 7884000_u64);
        _timeframeById::write(4_u16, 15768000_u64);
        _timeframeById::write(5_u16, 31536000_u64);
        // _timeframeById::write(6_u16, 60_u64);
        // _timeframeById::write(7_u16, 600_u64);

        _tokensAmountByTimeframeId::write(0_u16, as_u256(0_u128, 69444444400000_u128));
        _tokensAmountByTimeframeId::write(1_u16, as_u256(0_u128, 92592590000000_u128));
        _tokensAmountByTimeframeId::write(2_u16, as_u256(0_u128, 115740740000000_u128));
        _tokensAmountByTimeframeId::write(3_u16, as_u256(0_u128, 138888880000000_u128));
        _tokensAmountByTimeframeId::write(4_u16, as_u256(0_u128, 196759250000000_u128));
        _tokensAmountByTimeframeId::write(5_u16, as_u256(0_u128, 277777777000000_u128));
        // _tokensAmountByTimeframeId::write(6_u16, as_u256(0_u128, 69444444400000_u128));
        // _tokensAmountByTimeframeId::write(7_u16, as_u256(0_u128, 92592590000000_u128));

        _nftAdrs::write(nftAdrs);
        _tokenAdrs::write(tokenAdrs);
        _owner::write(owner);
        _safeClassHash::write(safeClassHash);
    }

    #[external]
    fn lock(tokenId:u256, timeframeId:u16, rdmSalt:felt252) {
        assert (!_isLockedTokenId::read(tokenId), 'Token is already locked');
        let caller=get_caller_address();
        let nftAdrs = _nftAdrs::read();
        let nftDispatcher = IERC721Dispatcher { contract_address: nftAdrs };
        let owner = nftDispatcher.ownerOf(tokenId);
        assert (caller == owner, 'Not the owner of the token');

        let safeAdrs = _safeByAdrs::read(owner);
        
        if(safeAdrs.into() == 0){
            let mut safeCalldata = ArrayTrait::new();
            safeCalldata.append(_nftAdrs::read().into());
            safeCalldata.append(_lockerSelfAdrs::read().into());
            safeCalldata.append(_owner::read().into());
            let result = deploy_syscall(_safeClassHash::read(), rdmSalt, safeCalldata.span(), false);
            let (safeAdrs, _) = result.unwrap_syscall();
            _safeByAdrs::write(owner, safeAdrs);
            _ownerOfSafe::write(safeAdrs, owner);
            _safeAdrsByTokenId::write(tokenId, safeAdrs);
            nftDispatcher.transferFrom(owner, safeAdrs, tokenId);
        }
        else {
            _safeAdrsByTokenId::write(tokenId, safeAdrs);
            nftDispatcher.transferFrom(owner, safeAdrs, tokenId);
        }
        _isLockedTokenId::write(tokenId, true);
        _timestampLocked::write(tokenId, get_block_timestamp());
        _timeframeIdByTokenId::write(tokenId, timeframeId);
    }

    fn _unlock(tokenId:u256, to: ContractAddress, nftDispatcher: IERC721Dispatcher, safeAdrs: ContractAddress) {
        let safeDispatcher = ISafeDispatcher { contract_address: safeAdrs };
        safeDispatcher.approveLocker(tokenId);
        nftDispatcher.transferFrom(safeAdrs, to, tokenId);
        _isLockedTokenId::write(tokenId, false);
    }

    fn _harvest(tokenId:u256, caller: ContractAddress, currentTimestamp: u64, amountToMint: u256) {
        let tokenAdrs = _tokenAdrs::read();
        let tokenDispatcher = IERC20Dispatcher { contract_address: tokenAdrs };
        tokenDispatcher.mint(caller, amountToMint);
        _lastHarvest::write(tokenId, currentTimestamp);
    }

    #[external]
    fn harvest(tokenId:u256) {
        assert (_isLockedTokenId::read(tokenId), 'Token is not locked');
        let caller=get_caller_address();
        let callerSafe = _safeByAdrs::read(caller);
        let nftAdrs = _nftAdrs::read();
        let nftDispatcher = IERC721Dispatcher { contract_address: nftAdrs };
        let tokenOwner = nftDispatcher.ownerOf(tokenId);
        assert (callerSafe == tokenOwner, 'Safe not the owner of the token');

        let timestampLocked = _timestampLocked::read(tokenId);
        let timeframeId = _timeframeIdByTokenId::read(tokenId);
        let timeframe = _timeframeById::read(timeframeId);
        let lastHarvest = _lastHarvest::read(tokenId);

        
        let currentTimestamp = get_block_timestamp();

        if(lastHarvest > timestampLocked){
            if(currentTimestamp >= timestampLocked + timeframe){
                let amount = _tokensAmountByTimeframeId::read(timeframeId);
                let rewardTime = (timestampLocked + timeframe - lastHarvest).into();
                let amountToMint = amount * as_u256(0_u128, rewardTime);
                _harvest(tokenId, caller, currentTimestamp, amountToMint);
                _unlock(tokenId, caller, nftDispatcher, callerSafe);
            }
            else {
                let amount = _tokensAmountByTimeframeId::read(timeframeId);
                let rewardTime = (currentTimestamp - lastHarvest).into();
                let amountToMint = amount * as_u256(0_u128, rewardTime);
                _harvest(tokenId, caller, currentTimestamp, amountToMint);
            }
        }
        else {
            if(currentTimestamp >= timestampLocked + timeframe){
                let amount = _tokensAmountByTimeframeId::read(timeframeId);
                let amountToMint = amount * as_u256(0_u128, timeframe.into());
                _harvest(tokenId, caller, currentTimestamp, amountToMint);
                _unlock(tokenId, caller, nftDispatcher, callerSafe);
            }
            else {
                let amount = _tokensAmountByTimeframeId::read(timeframeId);
                let rewardTime = (currentTimestamp - timestampLocked).into();
                let amountToMint = amount * as_u256(0_u128, rewardTime);
                _harvest(tokenId, caller, currentTimestamp, amountToMint);
            }
        }
    }

    #[view]
    fn getSafeByAdrs(owner:ContractAddress) -> ContractAddress {
        return _safeByAdrs::read(owner);
    }

    #[view]
    fn isLocked(tokenId:u256) -> bool {
        return _isLockedTokenId::read(tokenId);
    }

    #[view]
    fn getTimeframeId(tokenId:u256) -> u16 {
        return _timeframeIdByTokenId::read(tokenId);
    }

    #[view]
    fn getTimeframe(timeframeId:u16) -> u64 {
        return _timeframeById::read(timeframeId);
    }

    #[view]
    fn getTimestampLocked(tokenId:u256) -> u64 {
        return _timestampLocked::read(tokenId);
    }

    #[view]
    fn getLastHarvest(tokenId:u256) -> u64 {
        return _lastHarvest::read(tokenId);
    }

    // #[view]
    // fn get_implementation_hash() -> felt252 {
    //     return Proxy_implementation_hash::read();
    // }

    // Owner functions
    #[external]
    fn setTimeframe(timeframeId:u16, timeframe:u64) {
        let caller=get_caller_address();
        assert (caller == _owner::read(), 'Not the owner of the contract');
        _timeframeById::write(timeframeId, timeframe);
    }

    #[external]
    fn setTokensAmount(timeframeId:u16, amount:u256) {
        let caller=get_caller_address();
        assert (caller == _owner::read(), 'Not the owner of the contract');
        _tokensAmountByTimeframeId::write(timeframeId, amount);
    }

    #[external]
    fn setTokenAdrs(tokenAdrs:ContractAddress) {
        let caller=get_caller_address();
        assert (caller == _owner::read(), 'Not the owner of the contract');
        _tokenAdrs::write(tokenAdrs);
    }

    #[external]
    fn setNftAdrs(nftAdrs:ContractAddress) {
        let caller=get_caller_address();
        assert (caller == _owner::read(), 'Not the owner of the contract');
        _nftAdrs::write(nftAdrs);
    }

    #[external]
    fn setLockerSelfAdrs(lockerSelfAdrs:ContractAddress) {
        let caller=get_caller_address();
        assert (caller == _owner::read(), 'Not the owner of the contract');
        _lockerSelfAdrs::write(lockerSelfAdrs);
    }

    #[external]
    fn setSafeClassHash(safeClassHash:ClassHash) {
        let caller=get_caller_address();
        assert (caller == _owner::read(), 'Not the owner of the contract');
        _safeClassHash::write(safeClassHash);
    }

    #[external]
    fn transferOwnership(newOwner:ContractAddress) {
        let caller=get_caller_address();
        assert (caller == _owner::read(), 'Not the owner of the contract');
        _owner::write(newOwner);
    }

    #[external]
    fn upgrade(new_implementation: starknet::ClassHash) {
        let caller=get_caller_address();
        assert (caller == _owner::read(), 'Not the owner of the contract');
        starknet::replace_class_syscall(new_implementation);
    }
}