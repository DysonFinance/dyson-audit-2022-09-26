pragma solidity 0.8.17;

// SPDX-License-Identifier: AGPL-3.0

import "interfaces/IDysonPair.sol";
import "interfaces/IWETH.sol";
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
    uint private constant BALANCE_BASE_UNIT = 1e18;
    address public immutable WETH;

    address public owner;

    constructor(address _WETH, address _owner) {
        WETH = _WETH;
        owner = _owner;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "FORBIDDEN");
        _;
    }

    /// @notice Allow another address to transfer token from this contract
    /// @param tokenAddress Address of token to approve
    /// @param contractAddress Address to grant allowance
    function rely(address tokenAddress, address contractAddress) onlyOwner external {
        tokenAddress.safeApprove(contractAddress, type(uint).max);
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

    /// @notice Swap token0 for token1
    /// @param pair `Pair` contract address
    /// @param to Address that will receive token1
    /// @param input Amount of token0 to swap
    /// @param minOutput Minimum of token1 expected to receive
    /// @return output Amount of token1 received
    function swap0(address pair, address to, uint input, uint minOutput) external returns (uint output) {
        address token0 = IDysonPair(pair).token0();
        token0.safeTransferFrom(msg.sender, address(this), input);
        output = IDysonPair(pair).swap0in(to, input, minOutput);
    }

    /// @notice Swap token1 for token0
    /// @param pair `Pair` contract address
    /// @param to Address that will receive token0
    /// @param input Amount of token1 to swap
    /// @param minOutput Minimum of token0 expected to receive
    /// @return output Amount of token0 received
    function swap1(address pair, address to, uint input, uint minOutput) external returns (uint output) {
        address token1 = IDysonPair(pair).token1();
        token1.safeTransferFrom(msg.sender, address(this), input);
        output = IDysonPair(pair).swap1in(to, input, minOutput);
    }

    /// @notice Swap token0 for token1 and token0 is ETH
    /// @param pair `Pair` contract address
    /// @param to Address that will receive token1
    /// @param minOutput Minimum of token1 expected to receive
    /// @return output Amount of token1 received
    function swap0ETHIn(address pair, address to, uint minOutput) external payable returns (uint output) {
        IWETH(WETH).deposit{value: msg.value}();
        output = IDysonPair(pair).swap0in(to, msg.value, minOutput);
    }

    /// @notice Swap token1 for token0 and token1 is ETH
    /// @param pair `Pair` contract address
    /// @param to Address that will receive token0
    /// @param minOutput Minimum of token0 expected to receive
    /// @return output Amount of token0 received
    function swap1ETHIn(address pair, address to, uint minOutput) external payable returns (uint output) {
        IWETH(WETH).deposit{value: msg.value}();
        output = IDysonPair(pair).swap1in(to, msg.value, minOutput);
    }

    /// @notice Swap token0 for token1 and token1 is ETH
    /// @param pair `Pair` contract address
    /// @param to Address that will receive ETH
    /// @param input Amount of token0 to swap
    /// @param minOutput Minimum of ETH expected to receive
    /// @return output Amount of ETH received
    function swap0ETHOut(address pair, address to, uint input, uint minOutput) external returns (uint output) {
        address token0 = IDysonPair(pair).token0();
        token0.safeTransferFrom(msg.sender, address(this), input);
        output = IDysonPair(pair).swap0in(address(this), input, minOutput);
        IWETH(WETH).withdraw(output);
        to.safeTransferETH(output);
    }

    /// @notice Swap token1 for token0 and token0 is ETH
    /// @param pair `Pair` contract address
    /// @param to Address that will receive ETH
    /// @param input Amount of token1 to swap
    /// @param minOutput Minimum of ETH expected to receive
    /// @return output Amount of ETH received
    function swap1ETHOut(address pair, address to, uint input, uint minOutput) external returns (uint output) {
        address token1 = IDysonPair(pair).token1();
        token1.safeTransferFrom(msg.sender, address(this), input);
        output = IDysonPair(pair).swap1in(address(this), input, minOutput);
        IWETH(WETH).withdraw(output);
        to.safeTransferETH(output);
    }

    /// @notice Deposit token0
    /// @param pair `Pair` contract address
    /// @param to Address that will receive DysonPair note
    /// @param input Amount of token0 to deposit
    /// @param minOutput Minimum amount of token1 expected to receive if the swap is perfromed
    /// @param time Lock time
    /// @return output Amount of token1 received if the swap is performed
    function deposit0(address pair, address to, uint input, uint minOutput, uint time) external returns (uint output) {
        address token0 = IDysonPair(pair).token0();
        token0.safeTransferFrom(msg.sender, address(this), input);
        output = IDysonPair(pair).deposit0(to, input, minOutput, time);
    }

    /// @notice Deposit token1
    /// @param pair `Pair` contract address
    /// @param to Address that will receive DysonPair note
    /// @param input Amount of token1 to deposit
    /// @param minOutput Minimum amount of token0 expected to receive if the swap is perfromed
    /// @param time Lock time
    /// @return output Amount of token0 received if the swap is performed
    function deposit1(address pair, address to, uint input, uint minOutput, uint time) external returns (uint output) {
        address token1 = IDysonPair(pair).token1();
        token1.safeTransferFrom(msg.sender, address(this), input);
        output = IDysonPair(pair).deposit1(to, input, minOutput, time);
    }

    /// @notice Deposit token0 and token0 is ETH
    /// @param pair `Pair` contract address
    /// @param to Address that will receive DysonPair note
    /// @param minOutput Minimum amount of token1 expected to receive if the swap is perfromed
    /// @param time Lock time
    /// @return output Amount of token1 received if the swap is performed
    function deposit0ETH(address pair, address to, uint minOutput, uint time) external payable returns (uint output) {
        IWETH(WETH).deposit{value: msg.value}();
        output = IDysonPair(pair).deposit0(to, msg.value, minOutput, time);
    }

    /// @notice Deposit token1 and token1 is ETH
    /// @param pair `Pair` contract address
    /// @param to Address that will receive DysonPair note
    /// @param minOutput Minimum amount of token0 expected to receive if the swap is perfromed
    /// @param time Lock time
    /// @return output Amount of token0 received if the swap is performed
    function deposit1ETH(address pair, address to, uint minOutput, uint time) external payable returns (uint output) {
        IWETH(WETH).deposit{value: msg.value}();
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
