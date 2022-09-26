// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "src/DysonPair.sol";
import "src/DysonFactory.sol";
import "src/Dyson.sol";
import "src/DysonRouter.sol";
import "src/interfaces/IERC20.sol";
import "src/interfaces/IWETH.sol";
import "./TestUtils.sol";

contract WETHMock is DYSON {
    constructor(address _owner) DYSON(_owner) {}

    function deposit() public payable {
        balanceOf[msg.sender] += msg.value;
    }

    function withdraw(uint amount) public {
        require(balanceOf[msg.sender] >= amount);
        balanceOf[msg.sender] -= amount;
        payable(msg.sender).transfer(amount);
    }
}

contract DysonRouterTest is TestUtils {
    address testOwner = address(this);
    address WETH = address(new WETHMock(testOwner));
    address token0 = address(new DYSON(testOwner));
    address token1 = address(new DYSON(testOwner));
    DysonFactory factory = new DysonFactory(testOwner);
    DysonPair normalPair = DysonPair(factory.createPair(token0, token1));
    DysonPair weth0Pair = DysonPair(factory.createPair(WETH, token1)); // WETH is token0
    DysonPair weth1Pair = DysonPair(factory.createPair(token0, WETH)); // WETH is token1
    DysonRouter router = new DysonRouter(WETH, testOwner);

    bytes32 constant WITHDRAW_TYPEHASH = keccak256("withdraw(address operator,uint index,address to,uint deadline)");
    uint constant PREMIUM_BASE_UNIT = 1e18;
    uint constant INITIAL_LIQUIDITY_TOKEN = 10**24;

    // Handy accounts
    address alice = _nameToAddr("alice");
    address bob = _nameToAddr("bob");
    address zack = _nameToAddr("zack");
    uint constant INITIAL_WEALTH = 10**30;

    struct Note {
        uint token0Amt;
        uint token1Amt;
        uint due;
    }

    function setUp() public {
        // Make sure variable names are matched.
        assertEq(normalPair.token0(), token0);
        assertEq(normalPair.token1(), token1);
        assertEq(weth0Pair.token0(), WETH);
        assertEq(weth0Pair.token1(), token1);
        assertEq(weth1Pair.token0(), token0);
        assertEq(weth1Pair.token1(), WETH);

        // Initialize token0 and token1 for pairs.
        deal(token0, address(normalPair), INITIAL_LIQUIDITY_TOKEN);
        deal(token1, address(normalPair), INITIAL_LIQUIDITY_TOKEN);
        deal(token1, address(weth0Pair), INITIAL_LIQUIDITY_TOKEN);
        deal(token0, address(weth1Pair), INITIAL_LIQUIDITY_TOKEN);

        router.rely(token0, address(normalPair));
        router.rely(token1, address(normalPair));
        router.rely(token0, address(weth1Pair));
        router.rely(token1, address(weth0Pair));
        router.rely(WETH, address(weth0Pair));
        router.rely(WETH, address(weth1Pair));

        // Initialize WETH for pairs.
        deal(zack, INITIAL_LIQUIDITY_TOKEN * 2);
        vm.startPrank(zack);
        IWETH(WETH).deposit{value: INITIAL_LIQUIDITY_TOKEN * 2}();
        IWETH(WETH).transfer(address(weth0Pair), INITIAL_LIQUIDITY_TOKEN);
        IWETH(WETH).transfer(address(weth1Pair), INITIAL_LIQUIDITY_TOKEN);
    
        // Initialize tokens and eth for handy accounts.
        deal(token0, alice, INITIAL_WEALTH);
        deal(token1, alice, INITIAL_WEALTH);
        deal(alice, INITIAL_WEALTH);
        deal(token0, bob, INITIAL_WEALTH);
        deal(token1, bob, INITIAL_WEALTH);
        deal(bob, INITIAL_WEALTH);

        // Appoving.
        changePrank(alice);
        IERC20(token0).approve(address(router), type(uint).max);
        IERC20(token1).approve(address(router), type(uint).max);
        changePrank(bob);
        IERC20(token0).approve(address(router), type(uint).max);
        IERC20(token1).approve(address(router), type(uint).max);
        vm.stopPrank();

        // Labeling.
        vm.label(alice, "Alice");
        vm.label(bob, "Bob");
        vm.label(address(router), "Router");
        vm.label(address(normalPair), "Normal Pair");
        vm.label(address(weth0Pair), "WETH0 Pair");
        vm.label(address(weth1Pair), "WETH1 Pair");
        vm.label(token0, "Token 0");
        vm.label(token1, "Token 1");
        vm.label(WETH, "WETH");
    }

    function testNormalPairSwap01() public {
        uint oldToken0Balance = IERC20(token0).balanceOf(alice);
        uint oldToken1Balance = IERC20(token1).balanceOf(alice);
        address pair = address(normalPair);
        uint swapAmount = 10**18;
        uint output0; 
        uint output1;

        vm.startPrank(alice);
        output1 = router.swap0(pair, alice, swapAmount, 0);
        uint newToken0Balance = IERC20(token0).balanceOf(alice);
        uint newToken1Balance = IERC20(token1).balanceOf(alice);
        assertEq(newToken0Balance, oldToken0Balance - swapAmount);
        assertEq(newToken1Balance, oldToken1Balance + output1);

        output0 = router.swap1(pair, alice, output1, 0);  
        newToken0Balance = IERC20(token0).balanceOf(alice);
        newToken1Balance = IERC20(token1).balanceOf(alice);
        assertEq(newToken0Balance, oldToken0Balance - swapAmount + output0);
        assertEq(newToken1Balance, oldToken1Balance);
        assertTrue(output0 <= swapAmount);
    }

    function testNormalPairSwap10() public {
        uint oldToken0Balance = IERC20(token0).balanceOf(alice);
        uint oldToken1Balance = IERC20(token1).balanceOf(alice);
        address pair = address(normalPair);
        uint swapAmount = 10**18;
        uint output0; 
        uint output1;

        vm.startPrank(alice);
        output0 = router.swap1(pair, alice, swapAmount, 0);
        uint newToken0Balance = IERC20(token0).balanceOf(alice);
        uint newToken1Balance = IERC20(token1).balanceOf(alice);
        assertEq(newToken0Balance, oldToken0Balance + output0);
        assertEq(newToken1Balance, oldToken1Balance - swapAmount);

        output1 = router.swap0(pair, alice, output0, 0);
        newToken0Balance = IERC20(token0).balanceOf(alice);
        newToken1Balance = IERC20(token1).balanceOf(alice);
        assertEq(newToken0Balance, oldToken0Balance);
        assertEq(newToken1Balance, oldToken1Balance - swapAmount + output1);
        assertTrue(output1 <= swapAmount);
    }

    function testWeth0PairSwap01() public {
        uint oldToken0Balance = alice.balance;
        uint oldToken1Balance = IERC20(token1).balanceOf(alice);
        address pair = address(weth0Pair);
        uint swapAmount = 10**18;
        uint output0; 
        uint output1;

        vm.startPrank(alice);
        output1 = router.swap0ETHIn{value: swapAmount}(pair, alice, 0);
        uint newToken0Balance = alice.balance;
        uint newToken1Balance = IERC20(token1).balanceOf(alice);
        assertEq(newToken0Balance, oldToken0Balance - swapAmount);
        assertEq(newToken1Balance, oldToken1Balance + output1);

        output0 = router.swap1ETHOut(pair, alice, output1, 0);
        newToken0Balance = alice.balance;
        newToken1Balance = IERC20(token1).balanceOf(alice);
        assertEq(newToken0Balance, oldToken0Balance - swapAmount + output0);
        assertEq(newToken1Balance, oldToken1Balance);
        assertTrue(output0 <= swapAmount);
    }

    function testWeth0PairSwap10() public {
        uint oldToken0Balance = alice.balance;
        uint oldToken1Balance = IERC20(token1).balanceOf(alice);
        address pair = address(weth0Pair);
        uint swapAmount = 10**18;
        uint output0; 
        uint output1;

        vm.startPrank(alice);
        output0 = router.swap1ETHOut(pair, alice, swapAmount, 0);
        uint newToken0Balance = alice.balance;
        uint newToken1Balance = IERC20(token1).balanceOf(alice);
        assertEq(newToken0Balance, oldToken0Balance + output0);
        assertEq(newToken1Balance, oldToken1Balance - swapAmount);

        output1 = router.swap0ETHIn{value: output0}(pair, alice, 0);
        newToken0Balance = alice.balance;
        newToken1Balance = IERC20(token1).balanceOf(alice);
        assertEq(newToken0Balance, oldToken0Balance);
        assertEq(newToken1Balance, oldToken1Balance - swapAmount + output1);
        assertTrue(output1 <= swapAmount);
    }

    function testWeth1PairSwap01() public {
        uint oldToken0Balance = IERC20(token0).balanceOf(alice);
        uint oldToken1Balance = alice.balance;
        address pair = address(weth1Pair);
        uint swapAmount = 10**18;
        uint output0; 
        uint output1;

        vm.startPrank(alice);
        output1 = router.swap0ETHOut(pair, alice, swapAmount, 0);
        uint newToken0Balance = IERC20(token0).balanceOf(alice);
        uint newToken1Balance = alice.balance;
        assertEq(newToken0Balance, oldToken0Balance - swapAmount);
        assertEq(newToken1Balance, oldToken1Balance + output1);

        output0 = router.swap1ETHIn{value: output1}(pair, alice, 0);
        newToken0Balance = IERC20(token0).balanceOf(alice);
        newToken1Balance = alice.balance;
        assertEq(newToken0Balance, oldToken0Balance - swapAmount + output0);
        assertEq(newToken1Balance, oldToken1Balance);
        assertTrue(output0 <= swapAmount);
    }

    function testWeth1PairSwap10() public {
        uint oldToken0Balance = IERC20(token0).balanceOf(alice);
        uint oldToken1Balance = alice.balance;
        address pair = address(weth1Pair);
        uint swapAmount = 10**18;
        uint output0; 
        uint output1;

        vm.startPrank(alice);
        output0 = router.swap1ETHIn{value: swapAmount}(pair, alice, 0);
        uint newToken0Balance = IERC20(token0).balanceOf(alice);
        uint newToken1Balance = alice.balance;
        assertEq(newToken0Balance, oldToken0Balance + output0);
        assertEq(newToken1Balance, oldToken1Balance - swapAmount);

        output1 = router.swap0ETHOut(pair, alice, output0, 0);
        newToken0Balance = IERC20(token0).balanceOf(alice);
        newToken1Balance = alice.balance;
        assertEq(newToken0Balance, oldToken0Balance);
        assertEq(newToken1Balance, oldToken1Balance - swapAmount + output1);
        assertTrue(output1 <= swapAmount);
    }

    function testNormalPairDeposit() public {
        DysonPair pair = normalPair;
        uint oldToken0Balance = IERC20(token0).balanceOf(alice);
        uint oldToken1Balance = IERC20(token1).balanceOf(alice);
        uint depositAmount = 10**18;
        uint period = 1 days;
        uint premium = pair.getPremium(period);

        vm.startPrank(alice);
        uint output1 = router.deposit0(address(pair), alice, depositAmount, 0, period);
        uint output0 = router.deposit1(address(pair), alice, depositAmount, 0, period);

        (uint token0Amt, uint token1Amt, uint due) = pair.notes(alice, 0);
        assertEq(token0Amt, depositAmount * (premium + PREMIUM_BASE_UNIT) / PREMIUM_BASE_UNIT);
        assertEq(token1Amt, output1 * (premium + PREMIUM_BASE_UNIT) / PREMIUM_BASE_UNIT);
        assertEq(due, block.timestamp + period);
        
        (token0Amt, token1Amt, due) = pair.notes(alice, 1);
        assertEq(token0Amt, output0 * (premium + PREMIUM_BASE_UNIT) / PREMIUM_BASE_UNIT);
        assertEq(token1Amt, depositAmount * (premium + PREMIUM_BASE_UNIT) / PREMIUM_BASE_UNIT);
        assertEq(due, block.timestamp + period);

        uint newToken0Balance = IERC20(token0).balanceOf(alice);
        uint newToken1Balance = IERC20(token1).balanceOf(alice);
        assertEq(newToken0Balance, oldToken0Balance - depositAmount);
        assertEq(newToken1Balance, oldToken1Balance - depositAmount);
    }

    function testWeth0Deposit() public {
        DysonPair pair = weth0Pair;
        uint oldToken0Balance = alice.balance;
        uint oldToken1Balance = IERC20(token1).balanceOf(alice);
        uint depositAmount = 10**18;
        uint period = 1 days;
        uint premium = pair.getPremium(period);

        vm.startPrank(alice);
        uint output1 = router.deposit0ETH{value: depositAmount}(address(pair), alice, 0, period);
        uint output0 = router.deposit1(address(pair), alice, depositAmount, 0, period);

        (uint token0Amt, uint token1Amt, uint due) = pair.notes(alice, 0);
        assertEq(token0Amt, depositAmount * (premium + PREMIUM_BASE_UNIT) / PREMIUM_BASE_UNIT);
        assertEq(token1Amt, output1 * (premium + PREMIUM_BASE_UNIT) / PREMIUM_BASE_UNIT);
        assertEq(due, block.timestamp + period);
        
        (token0Amt, token1Amt, due) = pair.notes(alice, 1);
        assertEq(token0Amt, output0 * (premium + PREMIUM_BASE_UNIT) / PREMIUM_BASE_UNIT);
        assertEq(token1Amt, depositAmount * (premium + PREMIUM_BASE_UNIT) / PREMIUM_BASE_UNIT);
        assertEq(due, block.timestamp + period);

        uint newToken0Balance = alice.balance;
        uint newToken1Balance = IERC20(token1).balanceOf(alice);
        assertEq(newToken0Balance, oldToken0Balance - depositAmount);
        assertEq(newToken1Balance, oldToken1Balance - depositAmount);
    }

    function testWeth1Deposit() public {
        DysonPair pair = weth1Pair;
        uint oldToken0Balance = IERC20(token0).balanceOf(alice);
        uint oldToken1Balance = alice.balance;
        uint depositAmount = 10**18;
        uint period = 1 days;
        uint premium = pair.getPremium(period);

        vm.startPrank(alice);
        uint output1 = router.deposit0(address(pair), alice, depositAmount, 0, period);
        uint output0 = router.deposit1ETH{value: depositAmount}(address(pair), alice, 0, period);

        (uint token0Amt, uint token1Amt, uint due) = pair.notes(alice, 0);
        assertEq(token0Amt, depositAmount * (premium + PREMIUM_BASE_UNIT) / PREMIUM_BASE_UNIT);
        assertEq(token1Amt, output1 * (premium + PREMIUM_BASE_UNIT) / PREMIUM_BASE_UNIT);
        assertEq(due, block.timestamp + period);
        
        (token0Amt, token1Amt, due) = pair.notes(alice, 1);
        assertEq(token0Amt, output0 * (premium + PREMIUM_BASE_UNIT) / PREMIUM_BASE_UNIT);
        assertEq(token1Amt, depositAmount * (premium + PREMIUM_BASE_UNIT) / PREMIUM_BASE_UNIT);
        assertEq(due, block.timestamp + period);

        uint newToken0Balance = IERC20(token0).balanceOf(alice);
        uint newToken1Balance = alice.balance;
        assertEq(newToken0Balance, oldToken0Balance - depositAmount);
        assertEq(newToken1Balance, oldToken1Balance - depositAmount);
    }

    function testNormalPairWithdraw() public {
        DysonPair pair = normalPair;
        uint depositAmount = 10**18;
        uint period = 1 days;
        uint index = 0;

        vm.startPrank(alice);
        router.deposit0(address(pair), alice, depositAmount, 0, period);
        router.deposit1(address(pair), alice, depositAmount, 0, period);
        skip(period);

        uint deadline = block.timestamp + 1;
        uint oldToken0Balance = IERC20(token0).balanceOf(alice);
        uint oldToken1Balance = IERC20(token1).balanceOf(alice);
        bytes memory sig = _getWithdrawSig(address(pair), _nameToKey("alice"), index, alice, deadline);
        (uint token0Amt, uint token1Amt) = router.withdraw(address(pair), index, alice, deadline, sig);
        uint newToken0Balance = IERC20(token0).balanceOf(alice);
        uint newToken1Balance = IERC20(token1).balanceOf(alice);
        assertEq(newToken0Balance, oldToken0Balance + token0Amt);
        assertEq(newToken1Balance, oldToken1Balance + token1Amt);

        index = index + 1;
        oldToken0Balance = IERC20(token0).balanceOf(alice);
        oldToken1Balance = IERC20(token1).balanceOf(alice);
        sig = _getWithdrawSig(address(pair), _nameToKey("alice"), index, alice, deadline);
        (token0Amt, token1Amt) = router.withdraw(address(pair), index, alice, deadline, sig);
        newToken0Balance = IERC20(token0).balanceOf(alice);
        newToken1Balance = IERC20(token1).balanceOf(alice);
        assertEq(newToken0Balance, oldToken0Balance + token0Amt);
        assertEq(newToken1Balance, oldToken1Balance + token1Amt);
    }

    function testWeth0WithdrawETH() public {
        DysonPair pair = weth0Pair;
        uint depositAmount = 10**18;
        uint period = 1 days;
        uint index = 0;

        vm.startPrank(alice);
        router.deposit0ETH{value: depositAmount}(address(pair), alice, 0, period);
        router.deposit1(address(pair), alice, depositAmount, 0, period);
        skip(period);

        uint deadline = block.timestamp + 1;
        uint oldToken0Balance = alice.balance;
        uint oldToken1Balance = IERC20(token1).balanceOf(alice);
        bytes memory sig = _getWithdrawSig(address(pair), _nameToKey("alice"), index, address(router), deadline);
        (uint token0Amt, uint token1Amt) = router.withdrawETH(address(pair), index, alice, deadline, sig);
        uint newToken0Balance = alice.balance;
        uint newToken1Balance = IERC20(token1).balanceOf(alice);
        assertEq(newToken0Balance, oldToken0Balance + token0Amt);
        assertEq(newToken1Balance, oldToken1Balance + token1Amt);

        index = index + 1;
        oldToken0Balance = alice.balance;
        oldToken1Balance = IERC20(token1).balanceOf(alice);
        sig = _getWithdrawSig(address(pair), _nameToKey("alice"), index, address(router), deadline);
        (token0Amt, token1Amt) = router.withdrawETH(address(pair), index, alice, deadline, sig);
        newToken0Balance = alice.balance;
        newToken1Balance = IERC20(token1).balanceOf(alice);
        assertEq(newToken0Balance, oldToken0Balance + token0Amt);
        assertEq(newToken1Balance, oldToken1Balance + token1Amt);
    }

    function testWeth1WithdrawETH() public {
        DysonPair pair = weth1Pair;
        uint depositAmount = 10**18;
        uint period = 1 days;
        uint index = 0;

        vm.startPrank(alice);
        router.deposit0(address(pair), alice, depositAmount, 0, period);
        router.deposit1ETH{value: depositAmount}(address(pair), alice, 0, period);
        skip(period);

        uint deadline = block.timestamp + 1;
        uint oldToken0Balance = IERC20(token0).balanceOf(alice);
        uint oldToken1Balance = alice.balance;
        bytes memory sig = _getWithdrawSig(address(pair), _nameToKey("alice"), index, address(router), deadline);
        (uint token0Amt, uint token1Amt) = router.withdrawETH(address(pair), index, alice, deadline, sig);
        uint newToken0Balance = IERC20(token0).balanceOf(alice);
        uint newToken1Balance = alice.balance;
        assertEq(newToken0Balance, oldToken0Balance + token0Amt);
        assertEq(newToken1Balance, oldToken1Balance + token1Amt);

        index = index + 1;
        oldToken0Balance = IERC20(token0).balanceOf(alice);
        oldToken1Balance = alice.balance;
        sig = _getWithdrawSig(address(pair), _nameToKey("alice"), index, address(router), deadline);
        (token0Amt, token1Amt) = router.withdrawETH(address(pair), index, alice, deadline, sig);
        newToken0Balance = IERC20(token0).balanceOf(alice);
        newToken1Balance = alice.balance;
        assertEq(newToken0Balance, oldToken0Balance + token0Amt);
        assertEq(newToken1Balance, oldToken1Balance + token1Amt);
    }

    function testCannotWithdrawWithNotSelfSignedSig() public {
        uint index = 0;
        uint deadline = block.timestamp + 1;

        // sender == bob
        // signer == alice
        vm.startPrank(bob);
        bytes memory sig = _getWithdrawSig(address(normalPair), _nameToKey("alice"), index, alice, deadline);
        vm.expectRevert("INVALID_SIGNATURE");
        router.withdraw(address(normalPair), index, alice, deadline, sig); // to == alice
        vm.expectRevert("INVALID_SIGNATURE");
        router.withdraw(address(normalPair), index, bob, deadline, sig); // to == bob

        sig = _getWithdrawSig(address(weth0Pair), _nameToKey("alice"), index, address(router), deadline);
        vm.expectRevert("INVALID_SIGNATURE");
        router.withdrawETH(address(weth0Pair), index, alice, deadline, sig);
        vm.expectRevert("INVALID_SIGNATURE");
        router.withdrawETH(address(weth0Pair), index, bob, deadline, sig);

        sig = _getWithdrawSig(address(weth1Pair), _nameToKey("alice"), index, address(router), deadline);
        vm.expectRevert("INVALID_SIGNATURE");
        router.withdrawETH(address(weth1Pair), index, alice, deadline, sig);
        vm.expectRevert("INVALID_SIGNATURE");
        router.withdrawETH(address(weth1Pair), index, bob, deadline, sig);
    }

    function testCannotWithdrawWithExpiredSig() public {
        uint index = 0;
        uint deadline = block.timestamp + 1;
        skip(2);

        // sender == signer == alice
        vm.startPrank(alice);
        bytes memory sig = _getWithdrawSig(address(normalPair), _nameToKey("alice"), index, alice, deadline);
        vm.expectRevert("EXCEED_DEADLINE");
        router.withdraw(address(normalPair), index, alice, deadline, sig);

        sig = _getWithdrawSig(address(weth0Pair), _nameToKey("alice"), index, address(router), deadline);
        vm.expectRevert("EXCEED_DEADLINE");
        router.withdrawETH(address(weth0Pair), index, alice, deadline, sig);

        sig = _getWithdrawSig(address(weth1Pair), _nameToKey("alice"), index, address(router), deadline);
        vm.expectRevert("EXCEED_DEADLINE");
        router.withdrawETH(address(weth1Pair), index, alice, deadline, sig);
    }

    function _getWithdrawSig(address pair, uint fromKey, uint index, address to, uint deadline) private returns (bytes memory) {
        bytes32 structHash = keccak256(abi.encodePacked(WITHDRAW_TYPEHASH, address(router), index, to, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _getDysonPairDomainSeparator(pair), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(fromKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function _getDysonPairDomainSeparator(address pair) private view returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'),
                keccak256(bytes("DysonPair")),
                keccak256(bytes('1')),
                block.chainid,
                pair
            )
        );
    }
}