module diamond_clicker::game {
    use std::signer;
    use std::vector;

    use aptos_framework::timestamp;

    #[test_only]
    use aptos_framework::account;

    /*
    Errors
    DO NOT EDIT
    */
    const ERROR_GAME_STORE_DOES_NOT_EXIST: u64 = 0;
    const ERROR_UPGRADE_DOES_NOT_EXIST: u64 = 1;
    const ERROR_NOT_ENOUGH_DIAMONDS_TO_UPGRADE: u64 = 2;

    /*
    Const
    DO NOT EDIT
    */
    const POWERUP_NAMES: vector<vector<u8>> = vector[b"Bruh", b"Aptomingos", b"Aptos Monkeys"];
    // cost, dpm (diamonds per minute)
    const POWERUP_VALUES: vector<vector<u64>> = vector[
        vector[5, 5],
        vector[25, 30],
        vector[250, 350],
    ];

    /*
    Structs
    DO NOT EDIT
    */
    struct Upgrade has key, store, copy {
        name: vector<u8>,
        amount: u64
    }

    struct GameStore has key {
        diamonds: u64,
        upgrades: vector<Upgrade>,
        last_claimed_timestamp_seconds: u64,
    }

    /*
    Functions
    */

    public fun initialize_game(account: &signer) {
        let game_store = GameStore {
            diamonds: 0,
            upgrades: vector[],
            last_claimed_timestamp_seconds: timestamp::now_seconds(),
        };
        account::move_to(account, game_store);
    }

    public entry fun click(account: &signer) acquires GameStore {
        let account_address = signer::address_of(account);
        if (!exists<GameStore>(account_address)) {
            initialize_game(account);
        }
        let game_store = borrow_global_mut<GameStore>(account_address);
        game_store.diamonds += 1;
    }

    fun get_unclaimed_diamonds(account_address: address, current_timestamp_seconds: u64): u64 acquires GameStore {
        let game_store = borrow_global<GameStore>(account_address);
        let minutes_elapsed = (current_timestamp_seconds - game_store.last_claimed_timestamp_seconds) / 60;
        let mut unclaimed_diamonds = 0;
        for upgrade in &game_store.upgrades {
            let upgrade_index = get_upgrade_index(upgrade.name);
            let dpm = POWERUP_VALUES[upgrade_index][1];
            unclaimed_diamonds += dpm * upgrade.amount * minutes_elapsed;
        }
        unclaimed_diamonds
    }

    fun claim(account_address: address) acquires GameStore {
        let game_store = borrow_global_mut<GameStore>(account_address);
        let current_timestamp_seconds = timestamp::now_seconds();
        let unclaimed_diamonds = get_unclaimed_diamonds(account_address, current_timestamp_seconds);
        game_store.diamonds += unclaimed_diamonds;
        game_store.last_claimed_timestamp_seconds = current_timestamp_seconds;
    }

    public entry fun upgrade(account: &signer, upgrade_index: u64, upgrade_amount: u64) acquires GameStore {
        let account_address = signer::address_of(account);
        assert(exists<GameStore>(account_address), ERROR_GAME_STORE_DOES_NOT_EXIST);
        assert(upgrade_index < POWERUP_NAMES.length(), ERROR_UPGRADE_DOES_NOT_EXIST);

        claim(account_address);

        let game_store = borrow_global_mut<GameStore>(account_address);
        let upgrade_cost = POWERUP_VALUES[upgrade_index][0];
        let total_upgrade_cost = upgrade_cost * upgrade_amount;
        assert(game_store.diamonds >= total_upgrade_cost, ERROR_NOT_ENOUGH_DIAMONDS_TO_UPGRADE);

        let mut upgrade_existed = false;
        for upgrade in &mut game_store.upgrades {
            if (upgrade.name == POWERUP_NAMES[upgrade_index]) {
                upgrade.amount += upgrade_amount;
                upgrade_existed = true;
                break;
            }
        }
        
        if (!upgrade_existed) {
            let new_upgrade = Upgrade {
                name: POWERUP_NAMES[upgrade_index],
                amount: upgrade_amount,
            };
            vector::push_back(&mut game_store.upgrades, new_upgrade);
        }

        game_store.diamonds -= total_upgrade_cost;
    }

     #[view]
     public fun get_diamonds(account_address: address): u64 acquires GameStore {
         assert(exists<GameStore>(account_address), ERROR_GAME_STORE_DOES_NOT_EXIST);
         let game_store = borrow_global<GameStore>(account_address);
         let current_timestamp_seconds = timestamp::now_seconds();
         let unclaimed_diamonds = get_unclaimed_diamonds(account_address, current_timestamp_seconds);
         game_store.diamonds + unclaimed_diamonds
     }

     #[view]
     public fun get_diamonds_per_minute(account_address: address): u64 acquires GameStore {
         assert(exists<GameStore>(account_address), ERROR_GAME_STORE_DOES_NOT_EXIST);
         let game_store = borrow_global<GameStore>(account_address);
         let mut diamonds_per_minute = 0;
         for upgrade in &game_store.upgrades {
             let upgrade_index = get_upgrade_index(upgrade.name);
             let dpm = POWERUP_VALUES[upgrade_index][1];
             diamonds_per_minute += dpm * upgrade.amount;
         }
         diamonds_per_minute
     }

     #[view]
     public fun get_powerups(account_address: address): vector<Upgrade> acquires GameStore {
         assert(exists<GameStore>(account_address), ERROR_GAME_STORE_DOES_NOT_EXIST);
         let game_store = borrow_global<GameStore>(account_address);
         game_store.upgrades
     }

    /*
    Helper Functions
    */

    fun get_upgrade_index(upgrade_name: vector<u8>): u64 {
        let mut index = 0;
        while (index < POWERUP_NAMES.length()) {
            if (POWERUP_NAMES[index] == upgrade_name) {
                return index;
            }
            index += 1;
        }
        abort(ERROR_UPGRADE_DOES_NOT_EXIST)
    }

        /*
    Tests
    DO NOT EDIT
    */
    inline fun test_click_loop(signer: &signer, amount: u64) acquires GameStore {
        let i = 0;
        while (amount > i) {
            click(signer);
            i = i + 1;
        }
    }

    #[test(aptos_framework = @0x1, account = @0xCAFE, test_one = @0x12)]
    fun test_click_without_initialize_game(
        aptos_framework: &signer,
        account: &signer,
        test_one: &signer,
    ) acquires GameStore {
        timestamp::set_time_has_started_for_testing(aptos_framework);

        let aptos_framework_address = signer::address_of(aptos_framework);
        let account_address = signer::address_of(account);
        let test_one_address = signer::address_of(test_one);

        account::create_account_for_test(aptos_framework_address);
        account::create_account_for_test(account_address);

        click(test_one);

        let current_game_store = borrow_global<GameStore>(test_one_address);

        assert!(current_game_store.diamonds == 1, 0);
    }

    #[test(aptos_framework = @0x1, account = @0xCAFE, test_one = @0x12)]
    fun test_click_with_initialize_game(
        aptos_framework: &signer,
        account: &signer,
        test_one: &signer,
    ) acquires GameStore {
        timestamp::set_time_has_started_for_testing(aptos_framework);

        let aptos_framework_address = signer::address_of(aptos_framework);
        let account_address = signer::address_of(account);
        let test_one_address = signer::address_of(test_one);

        account::create_account_for_test(aptos_framework_address);
        account::create_account_for_test(account_address);

        click(test_one);

        let current_game_store = borrow_global<GameStore>(test_one_address);

        assert!(current_game_store.diamonds == 1, 0);

        click(test_one);

        let current_game_store = borrow_global<GameStore>(test_one_address);

        assert!(current_game_store.diamonds == 2, 1);
    }

    #[test(aptos_framework = @0x1, account = @0xCAFE, test_one = @0x12)]
    #[expected_failure(abort_code = 0, location = diamond_clicker::game)]
    fun test_upgrade_does_not_exist(
        aptos_framework: &signer,
        account: &signer,
        test_one: &signer,
    ) acquires GameStore {
        timestamp::set_time_has_started_for_testing(aptos_framework);

        let aptos_framework_address = signer::address_of(aptos_framework);
        let account_address = signer::address_of(account);

        account::create_account_for_test(aptos_framework_address);
        account::create_account_for_test(account_address);

        upgrade(test_one, 0, 1);
    }

    #[test(aptos_framework = @0x1, account = @0xCAFE, test_one = @0x12)]
    #[expected_failure(abort_code = 2, location = diamond_clicker::game)]
    fun test_upgrade_does_not_have_enough_diamonds(
        aptos_framework: &signer,
        account: &signer,
        test_one: &signer,
    ) acquires GameStore {
        timestamp::set_time_has_started_for_testing(aptos_framework);

        let aptos_framework_address = signer::address_of(aptos_framework);
        let account_address = signer::address_of(account);

        account::create_account_for_test(aptos_framework_address);
        account::create_account_for_test(account_address);

        click(test_one);
        upgrade(test_one, 0, 1);
    }

    #[test(aptos_framework = @0x1, account = @0xCAFE, test_one = @0x12)]
    fun test_upgrade_one(
        aptos_framework: &signer,
        account: &signer,
        test_one: &signer,
    ) acquires GameStore {
        timestamp::set_time_has_started_for_testing(aptos_framework);

        let aptos_framework_address = signer::address_of(aptos_framework);
        let account_address = signer::address_of(account);

        account::create_account_for_test(aptos_framework_address);
        account::create_account_for_test(account_address);

        test_click_loop(test_one, 5);
        upgrade(test_one, 0, 1);
    }

    #[test(aptos_framework = @0x1, account = @0xCAFE, test_one = @0x12)]
    fun test_upgrade_two(
        aptos_framework: &signer,
        account: &signer,
        test_one: &signer,
    ) acquires GameStore {
        timestamp::set_time_has_started_for_testing(aptos_framework);

        let aptos_framework_address = signer::address_of(aptos_framework);
        let account_address = signer::address_of(account);

        account::create_account_for_test(aptos_framework_address);
        account::create_account_for_test(account_address);

        test_click_loop(test_one, 25);

        upgrade(test_one, 1, 1);
    }

    #[test(aptos_framework = @0x1, account = @0xCAFE, test_one = @0x12)]
    fun test_upgrade_three(
        aptos_framework: &signer,
        account: &signer,
        test_one: &signer,
    ) acquires GameStore {
        timestamp::set_time_has_started_for_testing(aptos_framework);

        let aptos_framework_address = signer::address_of(aptos_framework);
        let account_address = signer::address_of(account);

        account::create_account_for_test(aptos_framework_address);
        account::create_account_for_test(account_address);

        test_click_loop(test_one, 250);

        upgrade(test_one, 2, 1);
    }
}