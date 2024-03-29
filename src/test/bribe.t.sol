// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "src/Bribe.sol";
import "src/Dyson.sol";
import "src/sDYSON.sol";
import "src/Gauge.sol";
import "./TestUtils.sol";

contract FarmMock {
    function setPoolRewardRate(address, uint, uint) pure external {}
}

contract BribeTest is TestUtils {
    address testOwner = address(this);
    address gov = address(new DYSON(testOwner));
    address sGov = address(new sDYSON(testOwner, gov));
    address farm = address(new FarmMock());
    uint constant INITIAL_WEIGHT = 10**24;
    uint constant INITIAL_BASE = 10**24;
    uint constant INITIAL_SLOPE = 10**24;
    Gauge gauge = new Gauge(farm, sGov, address(0), INITIAL_WEIGHT, INITIAL_BASE, INITIAL_SLOPE);
    Bribe bribe = new Bribe(address(gauge));
    address bribeToken = address(new DYSON(testOwner));

    // Handy accounts
    address alice = _nameToAddr("alice");
    address bob = _nameToAddr("bob");
    address briber = _nameToAddr("briber");
    uint constant INITIAL_WEALTH = 10**30;
    uint genesis;

    function setUp() public {
        deal(sGov, alice, INITIAL_WEALTH);
        deal(sGov, bob, INITIAL_WEALTH);
        vm.prank(alice);
        sDYSON(sGov).approve(address(gauge), INITIAL_WEALTH);
        vm.prank(bob);
        sDYSON(sGov).approve(address(gauge), INITIAL_WEALTH);

        deal(bribeToken, briber, INITIAL_WEALTH);
        vm.prank(briber);
        DYSON(bribeToken).approve(address(bribe), INITIAL_WEALTH);
        genesis = gauge.genesis();
    }

    function testCannotAddRewardForPreviousWeeks() public {
        skip(2 weeks);
        uint bribeWeek = 1 + genesis;
        uint bribeAmount = 100;
        vm.prank(briber);
        vm.expectRevert("CANNOT ADD FOR PREVIOUS WEEKS");
        bribe.addReward(bribeToken, bribeWeek, bribeAmount);
    }

    function testAddReward() public {
        uint bribeWeek = 1 + genesis;
        uint bribeAmount = 100;
        vm.prank(briber);
        bribe.addReward(bribeToken, bribeWeek, bribeAmount);
        assertEq(bribe.tokenRewardOfWeek(bribeToken, bribeWeek), bribeAmount);
    }

    function testCannotClaimBeforeWeekEnds() public {
        // thisWeek = 0
        uint thisWeek = genesis;
        uint weekNotEnded = 1 + genesis;
        vm.prank(alice);
        vm.expectRevert("NOT YET");
        bribe.claimReward(bribeToken, thisWeek);
        vm.expectRevert("NOT YET");
        bribe.claimReward(bribeToken, weekNotEnded);
    }

    function testCannotClaimTwice() public {
        vm.startPrank(alice);
        gauge.deposit(1); // Avoid division by zero.
        skip(1 weeks);
        bribe.claimReward(bribeToken, genesis);
        vm.expectRevert("CLAIMED");
        bribe.claimReward(bribeToken, genesis);
    }

    function testClaimReward() public {
        uint bribeAmount = 100;
        uint bribeWeek = genesis;
        vm.startPrank(briber);
        bribe.addReward(bribeToken, bribeWeek, bribeAmount);
        bribe.addReward(bribeToken, bribeWeek + 1, bribeAmount);
        bribe.addReward(bribeToken, bribeWeek + 2, bribeAmount);

        // Week  Alice  Bob  TotalSupply  Bribe
        //  0      1     0         1       100
        //  1      1     3         4       100
        //  2      3     7        10       100
        //  thisWeek = 3
        changePrank(alice);
        gauge.deposit(1);
        skip(1 weeks);
        changePrank(bob);
        gauge.deposit(3);
        skip(1 weeks);
        changePrank(alice);
        gauge.deposit(2);
        changePrank(bob);
        gauge.deposit(4);
        skip(1 weeks);
        gauge.tick();

        changePrank(alice);
        assertEq(bribe.claimReward(bribeToken, bribeWeek), bribeAmount);
        assertEq(DYSON(bribeToken).balanceOf(alice), bribeAmount);
        assertEq(bribe.claimReward(bribeToken, bribeWeek + 1), bribeAmount / 4);
        assertEq(DYSON(bribeToken).balanceOf(alice), bribeAmount + bribeAmount / 4);
        assertEq(bribe.claimReward(bribeToken, bribeWeek + 2), bribeAmount * 3 / 10);
        assertEq(DYSON(bribeToken).balanceOf(alice), bribeAmount + bribeAmount / 4 + bribeAmount * 3 / 10);

        changePrank(bob);
        assertEq(bribe.claimReward(bribeToken, bribeWeek), 0);
        assertEq(DYSON(bribeToken).balanceOf(bob), 0);
        assertEq(bribe.claimReward(bribeToken, bribeWeek + 1), bribeAmount * 3/ 4);
        assertEq(DYSON(bribeToken).balanceOf(bob), bribeAmount * 3 / 4);
        assertEq(bribe.claimReward(bribeToken, bribeWeek + 2), bribeAmount * 7 / 10);
        assertEq(DYSON(bribeToken).balanceOf(bob), bribeAmount * 3 / 4 + bribeAmount * 7 / 10);
    }
}