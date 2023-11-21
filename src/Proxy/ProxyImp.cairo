#[contract]
mod ProxyImp {
    struct Storage {
        _implementation: felt252,
        _admin: felt252,
        _initialized: bool,
    }

    #[external]
    fn initializer(proxy_admin: felt252) {
        assert(!_initialized::read(), 'Contract already initialized');
        _initialized::write(true);
        _admin::write(proxy_admin);
    }

    #[view]
    fn getImplementationHash() -> felt252 {
        return _implementation::read();
    }

    #[view]
    fn getAdmin() -> felt252 {
        return _admin::read();
    }
}
