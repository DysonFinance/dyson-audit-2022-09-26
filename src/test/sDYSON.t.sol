// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "src/sDYSON.sol";
import "src/Dyson.sol";
import "./TestUtils.sol";

contract MigrationMock {
    function onMigrationReceived(address, uint) pure external returns (bytes4) {
        return 0xc5b97e06;
    }
}

contract SDYSONTest is TestUtils {
    address testOwner = address(this);
    uint constant STAKING_RATE_BASE_UNIT = 1e18;
    DYSON dyson = new DYSON(testOwner);
    sDYSON sDyson = new sDYSON(testOwner, address(dyson));
    StakingRateModel currentModel;

    // Handy accounts
    address alice = _nameToAddr("alice");
    address bob = _nameToAddr("bob");
    uint immutable INITIAL_WEALTH = 10**30;

    function setUp() public {
        currentModel = new StakingRateModel(STAKING_RATE_BASE_UNIT / 16); // initialRate = 1
        sDyson.setStakingRateModel(address(currentModel));
        deal(address(dyson), alice, INITIAL_WEALTH);
        deal(address(dyson), bob, INITIAL_WEALTH);
        vm.prank(alice);
        dyson.approve(address(sDyson), INITIAL_WEALTH);
        vm.prank(bob);
        dyson.approve(address(sDyson), INITIAL_WEALTH);
    }

    function testCannotTransferOwnershipByNonOwner() public {
        vm.prank(alice);
        vm.expectRevert("FORBIDDEN");
        sDyson.transferOwnership(alice);
    }

    function testTransferOwnership() public {
        sDyson.transferOwnership(alice);
        assertEq(sDyson.owner(), alice);
    }

    function testCannotSetStakingRateModelByNonOwner() public {
        StakingRateModel newStakingRateModel = new StakingRateModel(1e18 / 16);
        vm.prank(alice);
        vm.expectRevert("FORBIDDEN");
        sDyson.setStakingRateModel(address(newStakingRateModel));
    }

    function testSetStakingRateModel() public {
        StakingRateModel newStakingRateModel = new StakingRateModel(1e18 / 16);
        sDyson.setStakingRateModel(address(newStakingRateModel));
        assertEq(address(sDyson.currentModel()), address(newStakingRateModel));
    }

    function testCannotSetMigrationByNonOwner() public {
        vm.prank(alice);
        vm.expectRevert("FORBIDDEN");
        sDyson.setMigration(address(5566));
    }

    function testSetMigration() public {
        sDyson.setMigration(address(5566));
        assertEq(sDyson.migration(), address(5566));
    }

    function testCannotStakeForInvalidDuration() public {
        vm.prank(alice);
        uint amount = 1;
        uint tooShortDuration = 30 minutes - 1;
        uint tooLongDuration = 1461 days + 1;
        vm.expectRevert("invalid lockup");
        sDyson.stake(alice, amount, tooShortDuration);
        vm.expectRevert("invalid lockup");
        sDyson.stake(alice, amount, tooLongDuration);
    }

    function testStake() public {
        vm.startPrank(alice);
        uint lockDuration = 30 days;
        uint amount = 100;
        uint sDYSONAmount = currentModel.stakingRate(lockDuration) * amount / STAKING_RATE_BASE_UNIT;
        sDyson.stake(alice, amount, lockDuration);
        assertEq(sDyson.balanceOf(alice), sDYSONAmount);
        assertEq(sDyson.dysonAmountStaked(alice), amount);
        assertEq(sDyson.votingPower(alice), sDYSONAmount);
    }

    function testStakeForOtherAccount() public {
        vm.startPrank(alice);
        uint lockDuration = 30 days;
        uint amount = 100;
        uint sDYSONAmount = currentModel.stakingRate(lockDuration) * amount / STAKING_RATE_BASE_UNIT;
        sDyson.stake(bob, amount, lockDuration);
        assertEq(sDyson.balanceOf(bob), sDYSONAmount);
        assertEq(sDyson.dysonAmountStaked(bob), amount);
        assertEq(sDyson.votingPower(bob), sDYSONAmount);
    }

    function testStakeMultipleVaults() public {
        vm.startPrank(alice);
        uint lockDuration1 = 30 days;
        uint amount1 = 100;
        uint sDYSONAmount1 = currentModel.stakingRate(lockDuration1) * amount1 / STAKING_RATE_BASE_UNIT;
        sDyson.stake(alice, amount1, lockDuration1);

        uint lockDuration2 = 60 days;
        uint amount2 = 200;
        uint sDYSONAmount2 = currentModel.stakingRate(lockDuration2) * amount2 / STAKING_RATE_BASE_UNIT;
        sDyson.stake(alice, amount2, lockDuration2);
        assertEq(sDyson.balanceOf(alice), sDYSONAmount1 + sDYSONAmount2);
        assertEq(sDyson.dysonAmountStaked(alice), amount1 + amount2);
        assertEq(sDyson.votingPower(alice), sDYSONAmount1 + sDYSONAmount2);
    }

    function testCannotUnstakeBeforeUnlocked() public {
        vm.startPrank(alice);
        uint lockDuration = 30 days;
        uint amount = 100;
        uint sDYSONAmount = currentModel.stakingRate(lockDuration) * amount / STAKING_RATE_BASE_UNIT;
        sDyson.stake(alice, amount, lockDuration);
        skip(lockDuration - 1);
        vm.expectRevert("locked");
        sDyson.unstake(alice, 0, sDYSONAmount);
    }

    function testCannotUnstakeMoreThanLockedAmount() public {
        vm.startPrank(alice);
        uint lockDuration = 30 days;
        uint amount = 100;
        uint sDYSONAmount = currentModel.stakingRate(lockDuration) * amount / STAKING_RATE_BASE_UNIT;
        sDyson.stake(alice, amount, lockDuration);
        skip(lockDuration);
        vm.expectRevert("exceed locked amount");
        sDyson.unstake(alice, 0, sDYSONAmount + 1);
    }

    function testCannotUnstakeWithoutEnoughSDYSON() public {
        vm.startPrank(alice);
        uint lockDuration = 30 days;
        uint amount = 100;
        uint sDYSONAmount = currentModel.stakingRate(lockDuration) * amount / STAKING_RATE_BASE_UNIT;
        sDyson.stake(alice, amount, lockDuration);
        skip(lockDuration);

        // Alice transfer sDyson to Bob, so she has no sDyson.
        sDyson.transfer(bob, sDYSONAmount);
        vm.expectRevert(stdError.arithmeticError);
        sDyson.unstake(alice, 0, sDYSONAmount);
    }

    function testCannotUnstakeZeroAmount() public {
        vm.startPrank(alice);
        uint lockDuration = 30 days;
        uint amount = 100;
        sDyson.stake(alice, amount, lockDuration);
        skip(lockDuration);

        vm.expectRevert("invalid input amount");
        sDyson.unstake(alice, 0, 0);
    }

    function testUnstake() public {
        vm.startPrank(alice);
        uint lockDuration = 30 days;
        uint amount = 100;
        uint sDYSONAmount = currentModel.stakingRate(lockDuration) * amount / STAKING_RATE_BASE_UNIT;
        sDyson.stake(alice, amount, lockDuration);
        skip(lockDuration);

        uint unstakesDYSONAmount = 1;
        uint unstakeAmount = amount * unstakesDYSONAmount / sDYSONAmount;
        sDyson.unstake(alice, 0, unstakesDYSONAmount);
        assertEq(sDyson.balanceOf(alice), sDYSONAmount - unstakesDYSONAmount);
        assertEq(sDyson.dysonAmountStaked(alice), amount - unstakeAmount);
        assertEq(sDyson.votingPower(alice), sDYSONAmount - unstakesDYSONAmount);
    }

    function testCannotRestakeBeforeStake() public {
        vm.startPrank(alice);
        uint lockDuration = 30 days;
        uint amount = 100;
        vm.expectRevert("invalid index");
        sDyson.restake(0, amount, lockDuration);
    }

    function testCannotRestakeNonExistedVault() public {
        vm.startPrank(alice);
        uint lockDuration = 30 days;
        uint amount = 100;
        sDyson.stake(alice, amount, lockDuration);

        uint nonExistedVaultId = 1;
        vm.expectRevert("invalid index");
        sDyson.restake(nonExistedVaultId, amount, lockDuration + 1);
    }

    function testCannotRestakeForInvalidDuration() public {
        vm.startPrank(alice);
        uint lockDuration = 30 days;
        uint amount = 100;
        sDyson.stake(alice, amount, lockDuration);
        skip(30 days);

        uint tooShortDuration = 30 minutes - 1;
        uint tooLongDuration = 1461 days + 1;
        vm.expectRevert("invalid lockup");
        sDyson.restake(0, amount, tooShortDuration);
        vm.expectRevert("invalid lockup");
        sDyson.restake(0, amount, tooLongDuration);
    }

    function testCannotRestakeForShorterLockDuration() public {
        vm.startPrank(alice);
        uint lockDuration = 30 days;
        uint amount = 100;
        sDyson.stake(alice, amount, lockDuration);

        vm.expectRevert("locked");
        sDyson.restake(0, amount, lockDuration - 1);

        skip(15 days);
        vm.expectRevert("locked");
        sDyson.restake(0, amount, lockDuration - 15 days - 1);
    }

    function testRestake() public {
        vm.startPrank(alice);
        uint lockDuration = 30 days;
        uint amount = 100;
        sDyson.stake(alice, amount, lockDuration);

        uint restakeLockDuration = 60 days;
        uint restakeAmount = 200;
        uint restakeSDYSONAmount = currentModel.stakingRate(restakeLockDuration) * (amount + restakeAmount) / STAKING_RATE_BASE_UNIT;
        sDyson.restake(0, restakeAmount, restakeLockDuration);
        assertEq(sDyson.balanceOf(alice), restakeSDYSONAmount);
        assertEq(sDyson.dysonAmountStaked(alice), amount + restakeAmount);
        assertEq(sDyson.votingPower(alice), restakeSDYSONAmount);
    }

    function testCannotMigrateWithoutMigration() public {
        vm.startPrank(alice);
        vm.expectRevert("CANNOT MIGRATE");
        sDyson.migrate(0);
    }

    function testCannotMigrateNonExistedVault() public {
        sDyson.setMigration(address(5566));
        vm.startPrank(alice);
        vm.expectRevert("INVALID VAULT");
        sDyson.migrate(0);
    }

    function testMirgate() public {
        MigrationMock migration = new MigrationMock();
        sDyson.setMigration(address(migration));

        vm.startPrank(alice);
        uint lockDuration = 30 days;
        uint amount = 100;
        sDyson.stake(alice, amount, lockDuration);
        sDyson.migrate(0);
        assertEq(sDyson.dysonAmountStaked(alice), 0);
        assertEq(sDyson.votingPower(alice), 0);
    }
}