// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "src/DysonPair.sol";
import "src/DysonFactory.sol";
import "src/Dyson.sol";
import "./TestUtils.sol";

contract DysonPairTest is TestUtils {
    address testOwner = address(this);
    address token0 = address(new DYSON(testOwner));
    address token1 = address(new DYSON(testOwner));
    DysonFactory factory = new DysonFactory(testOwner);
    DysonPair pair = DysonPair(factory.createPair(token0, token1));

    uint immutable INITIAL_LIQUIDITY_TOKEN0 = 10**24;
    uint immutable INITIAL_LIQUIDITY_TOKEN1 = 10**24;

    // Handy accounts
    address alice = _nameToAddr("alice");
    address bob = _nameToAddr("bob");

    uint immutable INITIAL_WEALTH = 10**30;

    function setUp() public {
        // Initialize liquidity of Pair.
        deal(token0, address(pair), INITIAL_LIQUIDITY_TOKEN0);
        deal(token1, address(pair), INITIAL_LIQUIDITY_TOKEN1);

        // Initialize handy accounts for testing.
        deal(token0, alice, INITIAL_WEALTH);
        deal(token1, alice, INITIAL_WEALTH);
        deal(token0, bob, INITIAL_WEALTH);
        deal(token1, bob, INITIAL_WEALTH);
        vm.startPrank(alice);
        IERC20(token0).approve(address(pair), INITIAL_WEALTH);
        IERC20(token1).approve(address(pair), INITIAL_WEALTH);
        changePrank(bob);
        IERC20(token0).approve(address(pair), INITIAL_WEALTH);
        IERC20(token1).approve(address(pair), INITIAL_WEALTH);
        vm.stopPrank();
    }

    function testCannotDepositIfSlippageTooHigh() public {
        uint depositAmount = 10 * 10**18;
        vm.prank(bob);
        vm.expectRevert("SLIPPAGE");
        pair.deposit0(bob, depositAmount, depositAmount, 1 days);
        vm.expectRevert("SLIPPAGE");
        pair.deposit1(bob, depositAmount, depositAmount, 1 days);
    }

    function testCannotDepositWithInvalidPeriod() public {
        uint depositAmount = 10 * 10**18;
        vm.prank(bob);
        vm.expectRevert("INVALID_TIME");
        pair.deposit0(bob, depositAmount, 0, 2 days);
        vm.expectRevert("INVALID_TIME");
        pair.deposit1(bob, depositAmount, 0, 2 days);
    }

    function testDeposit0() public {
        uint depositAmount = 10 * 10**18;
        vm.startPrank(bob);
        pair.deposit0(bob, depositAmount, 0, 1 days);
        pair.deposit0(bob, depositAmount, 0, 3 days);
        pair.deposit0(bob, depositAmount, 0, 7 days);
        pair.deposit0(bob, depositAmount, 0, 30 days);
    }

    function testDeposit1() public {
        uint depositAmount = 10 * 10**18;
        vm.startPrank(bob);
        pair.deposit1(bob, depositAmount, 0, 1 days);
        pair.deposit1(bob, depositAmount, 0, 3 days);
        pair.deposit1(bob, depositAmount, 0, 7 days);
        pair.deposit1(bob, depositAmount, 0, 30 days);
    }

    function testCannotWithdrawNonExistNote() public {
        vm.startPrank(bob);
        vm.expectRevert("INVALID_NOTE");
        pair.withdraw(0);
        vm.expectRevert("INVALID_NOTE");
        pair.withdraw(1);
    }

    function testCannotEarlyWithdraw() public {
        uint depositAmount = 10 * 10**18;
        vm.startPrank(bob);
        pair.deposit0(bob, depositAmount, 0, 1 days); // Note 0
        pair.deposit1(bob, depositAmount, 0, 1 days); // Note 1

        vm.expectRevert("EARLY_WITHDRAWAL");
        pair.withdraw(0);
        vm.expectRevert("EARLY_WITHDRAWAL");
        pair.withdraw(1);
    }

    function testWithdraw0() public {
        uint depositAmount = 10 * 10**18;
        vm.startPrank(bob);
        pair.deposit0(bob, depositAmount, 0, 1 days);

        skip(1 days);
        pair.withdraw(0);
    }

    function testWithdraw1() public {
        uint depositAmount = 10 * 10**18;
        vm.startPrank(bob);
        pair.deposit1(bob, depositAmount, 0, 1 days);

        skip(1 days);
        pair.withdraw(0);
    }

    function testCannotWithdrawSameNote() public {
        uint depositAmount = 10 * 10**18;
        vm.startPrank(bob);
        pair.deposit0(bob, depositAmount, 0, 1 days); // Note 0
        pair.deposit1(bob, depositAmount, 0, 1 days); // Note 1

        skip(1 days);
        pair.withdraw(0);
        pair.withdraw(1);
        vm.expectRevert("INVALID_NOTE");
        pair.withdraw(0);
        vm.expectRevert("INVALID_NOTE");
        pair.withdraw(1);
    }

    function testCannotSetBasisByUser() public {
        vm.prank(bob);
        vm.expectRevert("FORBIDDEN");
        pair.setBasis(0);
    }

    function testCannotSetHalfLifeByUser() public {
        vm.prank(bob);
        vm.expectRevert("FORBIDDEN");
        pair.setHalfLife(0);
    }

    function testCannotSetFarmByUser() public {
        vm.prank(bob);
        vm.expectRevert("FORBIDDEN");
        pair.setFarm(address(0));
    }

    function testCannotSetFeeToByUser() public {
        vm.prank(bob);
        vm.expectRevert("FORBIDDEN");
        pair.setFeeTo(address(0));
    }

    function testRescueERC20() public {
        address token2 = address(new DYSON(testOwner));
        deal(token2, address(pair), INITIAL_WEALTH);
        pair.rescueERC20(token2, bob, INITIAL_WEALTH);
        assertEq(IERC20(token2).balanceOf(bob), INITIAL_WEALTH);
    }

    function testCannotSwapIfSlippageTooHigh() public {
        uint swapAmount = 10 * 10**18;
        uint output0; 
        uint output1;
        vm.startPrank(bob);
        vm.expectRevert("SLIPPAGE");
        output1 = pair.swap0in(bob, swapAmount, swapAmount);
        vm.expectRevert("SLIPPAGE");
        output0 = pair.swap1in(bob, swapAmount, swapAmount);
    }

    function testSwap01() public {
        uint swapAmount = 10 * 10**18;
        uint output0; 
        uint output1;
        vm.startPrank(bob);
        output1 = pair.swap0in(bob, swapAmount, 0);
        output0 = pair.swap1in(bob, output1, 0);
        assertTrue(output0 <= swapAmount);

        changePrank(alice);
        output1 = pair.swap0in(alice, swapAmount, 0);
        skip(1 hours);
        output0 = pair.swap1in(alice, output1, 0);
        assertTrue(output0 <= swapAmount);
    }

    function testSwap10() public {
        uint swapAmount = 10 * 10**18;
        uint output0; 
        uint output1;
        vm.startPrank(bob);
        vm.expectRevert("SLIPPAGE");
        output0 = pair.swap1in(bob, swapAmount, swapAmount);
        output0 = pair.swap1in(bob, swapAmount, 0);
        output1 = pair.swap0in(bob, output0, 0);
        assertTrue(output1 <= swapAmount);

        changePrank(alice);
        output0 = pair.swap1in(alice, swapAmount, 0);
        skip(1 hours);
        output1 = pair.swap0in(alice, output0, 0);
        assertTrue(output1 <= swapAmount);
    }
}