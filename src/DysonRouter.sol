pragma solidity 0.8.17;

// SPDX-License-Identifier: AGPL-3.0

import "interfaces/IDysonPair.sol";
import "interfaces/IWETH.sol";
import "interfaces/IDysonFactory.sol";
import "./SqrtMath.sol";
import "./TransferHelper.sol";

/// @title Router contract for all DysonPair contracts
/// @notice Users are expected to swap, deposit and withdraw via this contract
/// @dev IMPORTANT: Fund stuck or send to this contract is free for grab as `pair` param
/// in each swap functions is passed in and not validated so everyone can implement their
/// own `pair` contract and transfer the fund away.
contract DysonRouter {
    using SqrtMath for *;
    using TransferHelper for address;

    uint private constant MAX_FEE_RATIO = 2**64;
    address public immutable WETH;
    address public immutable DYSON_FACTORY;
    bytes32 public immutable CODE_HASH;

    address public owner;

    event TransferOwnership(address newOwner);

    constructor(address _WETH, address _owner, address _factory) {
        require(_owner != address(0), "OWNER_CANNOT_BE_ZERO");
        require(_WETH != address(0), "INVALID_WETH");
        WETH = _WETH;
        owner = _owner;
        DYSON_FACTORY = _factory;
        CODE_HASH = IDysonFactory(DYSON_FACTORY).getInitCodeHash();
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "FORBIDDEN");
        _;
    }

    // returns sorted token addresses, used to handle return values from pairs sorted in this order
    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, 'IDENTICAL_ADDRESSES');
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'ZERO_ADDRESS');
    }

    // calculates the CREATE2 address for a pair without making any external calls
    function pairFor(address factory, bytes32 initCodeHash, address tokenA, address tokenB, uint id) internal pure returns (address pair) {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        pair = address(uint160(uint(keccak256(abi.encodePacked(
                hex'ff',
                factory,
                keccak256(abi.encodePacked(token0, token1, id)), //salt
                initCodeHash
            )))));
    }

    function transferOwnership(address _owner) external onlyOwner {
        owner = _owner;

        emit TransferOwnership(_owner);
    }

    /// @notice Allow another address to transfer token from this contract
    /// @param tokenAddress Address of token to approve
    /// @param contractAddress Address to grant allowance
    /// @param enable True to enable allowance. False otherwise.
    function rely(address tokenAddress, address contractAddress, bool enable) onlyOwner external {
        tokenAddress.safeApprove(contractAddress, enable ? type(uint).max : 0);
    }

    /// @notice rescue token stucked in this contract
    /// @param tokenAddress Address of token to be rescued
    /// @param to Address that will receive token
    /// @param amount Amount of token to be rescued
    function rescueERC20(address tokenAddress, address to, uint256 amount) onlyOwner external {
        tokenAddress.safeTransfer(to, amount);
    }

    /// @notice This contract can only receive ETH coming from WETH contract,
    /// i.e., when it withdraws from WETH
    receive() external payable {
        require(msg.sender == WETH);
    }

    /// @notice Swap tokenIn for tokenOut
    /// @param tokenIn Address of spent token
    /// @param tokenOut Address of received token
    /// @param index Number of pair instance
    /// @param to Address that will receive tokenOut
    /// @param input Amount of tokenIn to swap
    /// @param minOutput Minimum of tokenOut expected to receive
    /// @return output Amount of tokenOut received
    function swap(address tokenIn, address tokenOut, uint index, address to, uint input, uint minOutput) external returns (uint output) {
        address pair = pairFor(DYSON_FACTORY, CODE_HASH, tokenIn, tokenOut, index);
        (address token0,) = sortTokens(tokenIn, tokenOut);
        tokenIn.safeTransferFrom(msg.sender, address(this), input);
        if(tokenIn == token0)
            output = IDysonPair(pair).swap0in(to, input, minOutput);
        else
            output = IDysonPair(pair).swap1in(to, input, minOutput);
    }

    /// @notice Swap ETH for tokenOut
    /// @param tokenOut Address of received token
    /// @param index Number of pair instance
    /// @param to Address that will receive tokenOut
    /// @param minOutput Minimum of token1 expected to receive
    /// @return output Amount of tokenOut received
    function swapETHIn(address tokenOut, uint index, address to, uint minOutput) external payable returns (uint output) {
        address pair = pairFor(DYSON_FACTORY, CODE_HASH, tokenOut, WETH, index);
        (address token0,) = sortTokens(WETH, tokenOut);
        IWETH(WETH).deposit{value: msg.value}();
        if(WETH == token0)
            output = IDysonPair(pair).swap0in(to, msg.value, minOutput);
        else
            output = IDysonPair(pair).swap1in(to, msg.value, minOutput);
    }

    /// @notice Swap tokenIn for ETH
    /// @param tokenIn Address of spent token
    /// @param index Number of pair instance
    /// @param to Address that will receive ETH
    /// @param input Amount of tokenIn to swap
    /// @param minOutput Minimum of ETH expected to receive
    /// @return output Amount of ETH received
    function swapETHOut(address tokenIn, uint index, address to, uint input, uint minOutput) external returns (uint output) {
        address pair = pairFor(DYSON_FACTORY, CODE_HASH, tokenIn, WETH, index);
        (address token0,) = sortTokens(WETH, tokenIn);
        tokenIn.safeTransferFrom(msg.sender, address(this), input);
        if(WETH == token0)
            output = IDysonPair(pair).swap1in(address(this), input, minOutput);
        else
            output = IDysonPair(pair).swap0in(address(this), input, minOutput);
        IWETH(WETH).withdraw(output);
        to.safeTransferETH(output);
    }

    /// @notice Deposit tokenIn
    /// @param tokenIn Address of spent token
    /// @param tokenOut Address of received token
    /// @param index Number of pair instance
    /// @param to Address that will receive DysonPair note
    /// @param input Amount of tokenIn to deposit
    /// @param minOutput Minimum amount of tokenOut expected to receive if the swap is perfromed
    /// @param time Lock time
    /// @return output Amount of tokenOut received if the swap is performed
    function deposit(address tokenIn, address tokenOut, uint index, address to, uint input, uint minOutput, uint time) external returns (uint output) {
        address pair = pairFor(DYSON_FACTORY, CODE_HASH, tokenIn, tokenOut, index);
        (address token0,) = sortTokens(tokenIn, tokenOut);
        tokenIn.safeTransferFrom(msg.sender, address(this), input);
        if(tokenIn == token0)
            output = IDysonPair(pair).deposit0(to, input, minOutput, time);
        else
            output = IDysonPair(pair).deposit1(to, input, minOutput, time);
    }

    /// @notice Deposit ETH
    /// @param tokenOut Address of received token
    /// @param index Number of pair instance
    /// @param to Address that will receive DysonPair note
    /// @param minOutput Minimum amount of tokenOut expected to receive if the swap is perfromed
    /// @param time Lock time
    /// @return output Amount of tokenOut received if the swap is performed
    function depositETH(address tokenOut, uint index, address to, uint minOutput, uint time) external payable returns (uint output) {
        address pair = pairFor(DYSON_FACTORY, CODE_HASH, tokenOut, WETH, index);
        (address token0,) = sortTokens(WETH, tokenOut);
        IWETH(WETH).deposit{value: msg.value}();
        if(WETH == token0)
            output = IDysonPair(pair).deposit0(to, msg.value, minOutput, time);
        else
            output = IDysonPair(pair).deposit1(to, msg.value, minOutput, time);
    }

    /// @notice Withdrw DysonPair note.
    /// User who signs the withdraw signature must be the one who calls this function
    /// @param pair `Pair` contract address
    /// @param index Index of the note to withdraw
    /// @param to Address that will receive either token0 or token1
    /// @param deadline Deadline when the withdraw signature expires
    /// @param sig Withdraw signature
    /// @return token0Amt Amount of token0 withdrawn
    /// @return token1Amt Amount of token1 withdrawn
    function withdraw(address pair, uint index, address to, uint deadline, bytes calldata sig) external returns (uint token0Amt, uint token1Amt) {
        return IDysonPair(pair).withdrawWithSig(msg.sender, index, to, deadline, sig);
    }

    /// @notice Withdrw DysonPair note and if either token0 or token1 withdrawn is WETH, withdraw from WETH and send ETH to receiver.
    /// User who signs the withdraw signature must be the one who calls this function
    /// @param pair `Pair` contract address
    /// @param index Index of the note to withdraw
    /// @param to Address that will receive either token0 or token1
    /// @param deadline Deadline when the withdraw signature expires
    /// @param sig Withdraw signature
    /// @return token0Amt Amount of token0 withdrawn
    /// @return token1Amt Amount of token1 withdrawn
    function withdrawETH(address pair, uint index, address to, uint deadline, bytes calldata sig) external returns (uint token0Amt, uint token1Amt) {
        (token0Amt, token1Amt) = IDysonPair(pair).withdrawWithSig(msg.sender, index, address(this), deadline, sig);
        address token0 = IDysonPair(pair).token0();
        address token = token0Amt > 0 ? token0 : IDysonPair(pair).token1();
        uint amount = token0Amt > 0 ? token0Amt : token1Amt;
        if (token == WETH) {
            IWETH(WETH).withdraw(amount);
            to.safeTransferETH(amount);
        } else {
            token.safeTransfer(to, amount);
        }
    }

    /// @notice Calculate the price of token1 in token0
    /// Formula:
    /// amount1 = amount0 * reserve1 * sqrt(1-fee0) / reserve0 / sqrt(1-fee1)
    /// which can be transformed to:
    /// amount1 = sqrt( amount0**2 * (1-fee0) / (1-fee1) ) * reserve1 / reserve0
    /// @param pair `Pair` contract address
    /// @param token0Amt Amount of token0
    /// @return token1Amt Amount of token1
    function fairPrice(address pair, uint token0Amt) external view returns (uint token1Amt) {
        (uint reserve0, uint reserve1) = IDysonPair(pair).getReserves();
        (uint64 _fee0, uint64 _fee1) = IDysonPair(pair).getFeeRatio();
        return (token0Amt**2 * (MAX_FEE_RATIO - _fee0) / (MAX_FEE_RATIO - _fee1)).sqrt() * reserve1 / reserve0;
    }
}
