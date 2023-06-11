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
        amount: u64,
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
        // move_to account with new GameStore
        move_to(account, GameStore {
            diamonds: 0,
            upgrades: vector<Upgrade>(),
            last_claimed_timestamp_seconds: timestamp::get_seconds(),
        });
    }

    public entry fun click(account: &signer) acquires GameStore {
        // check if GameStore does not exist - if not, initialize_game
        if !exists<GameStore>(account) {
            initialize_game(account);
        }

        // increment game_store.diamonds by +1
        update<GameStore>(account, |game_store| {
            game_store.diamonds += 1;
        });
    }

    fun get_unclaimed_diamonds(account_address: address, current_timestamp_seconds: u64): u64 acquires GameStore {
        let unclaimed_diamonds = 0;

        // loop over game_store.upgrades - if the powerup exists then calculate the dpm and minutes_elapsed to add the amount to the unclaimed_diamonds
        let game_store = read<GameStore>(account_address);
        for upgrade in game_store.upgrades.iter() {
            let powerup_index = u32::from(upgrade.name[0]);
            let powerup_dpm = POWERUP_VALUES[powerup_index as usize][1];
            let minutes_elapsed = (current_timestamp_seconds - game_store.last_claimed_timestamp_seconds) / 60;
            unclaimed_diamonds += powerup_dpm * minutes_elapsed * upgrade.amount;
        }

        // return unclaimed_diamonds
        unclaimed_diamonds
    }

    fun claim(account_address: address) acquires GameStore {
        // set game_store.diamonds to current diamonds + unclaimed_diamonds
        let current_timestamp_seconds = timestamp::get_seconds();
        let current_diamonds = get_diamonds(account_address);
        let unclaimed_diamonds = get_unclaimed_diamonds(account_address, current_timestamp_seconds);
        let total_diamonds = current_diamonds + unclaimed_diamonds;
        update<GameStore>(account_address, |game_store| {
            game_store.diamonds = total_diamonds;
            game_store.last_claimed_timestamp_seconds = current_timestamp_seconds;
        });
    }

    public entry fun upgrade(account: &signer, upgrade_index: u64, upgrade_amount: u64) acquires GameStore {
        // check that the game store exists
        assert(exists<GameStore>(account), ERROR_GAME_STORE_DOES_NOT_EXIST);

        // check the powerup_names length is greater than or equal to upgrade_index
        assert(upgrade_index < POWERUP_NAMES.len() as u64, ERROR_UPGRADE_DOES_NOT_EXIST);

        let account_address = signer::address_of(account);

        // claim for account address
        claim(account_address);

        // check that the user has enough coins to make the current upgrade
        let total_upgrade_cost = POWERUP_VALUES[upgrade_index as usize][0] * upgrade_amount;
        let current_diamonds = get_diamonds(account_address);
        assert(current_diamonds >= total_upgrade_cost, ERROR_NOT_ENOUGH_DIAMONDS_TO_UPGRADE);

        // loop through game_store upgrades - if the upgrade exists then increment but the upgrade_amount
        let mut upgrade_existed = false;
        update<GameStore>(account_address, |game_store| {
            for upgrade in game_store.upgrades.iter_mut() {
                if upgrade.name == POWERUP_NAMES[upgrade_index as usize] {
                    upgrade.amount += upgrade_amount;
                    upgrade_existed = true;
                    break;
                }
            }
            if !upgrade_existed {
                game_store.upgrades.push(Upgrade {
                    name: POWERUP_NAMES[upgrade_index as usize].clone(),
                    amount: upgrade_amount,
                });
            }
            game_store.diamonds -= total_upgrade_cost;
        });
    }

    // ...

    #[view]
    public fun get_diamonds(account_address: address): u64 acquires GameStore {
        // return game_store.diamonds + unclaimed_diamonds
        let current_timestamp_seconds = timestamp::get_seconds();
        let current_diamonds = read::<GameStore>(account_address).diamonds;
        let unclaimed_diamonds = get_unclaimed_diamonds(account_address, current_timestamp_seconds);
        current_diamonds + unclaimed_diamonds
    }

    #[view]
    public fun get_diamonds_per_minute(account_address: address): u64 acquires GameStore {
        let diamonds_per_minute = 0;

        // loop over game_store.upgrades - calculate dpm * current_upgrade.amount to get the total diamonds_per_minute
        let game_store = read::<GameStore>(account_address);
        for upgrade in game_store.upgrades.iter() {
            let powerup_index = u32::from(upgrade.name[0]);
            let powerup_dpm = POWERUP_VALUES[powerup_index as usize][1];
            diamonds_per_minute += powerup_dpm * upgrade.amount;
        }

        // return diamonds_per_minute of all the user's powerups
        diamonds_per_minute
    }

    #[view]
    public fun get_powerups(account_address: address): vector<Upgrade> acquires GameStore {
        // return game_store.upgrades
        read::<GameStore>(account_address).upgrades.clone()
    }

    /*
    Tests
    DO NOT EDIT
    */
    fun test_click_loop(signer: &signer, amount: u64) acquires GameStore {
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