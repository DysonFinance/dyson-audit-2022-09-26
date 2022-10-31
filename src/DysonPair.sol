pragma solidity 0.8.17;

// SPDX-License-Identifier: AGPL-3.0

import "interfaces/IERC20.sol";
import "interfaces/IFarm.sol";
import "interfaces/IDysonFactory.sol";
import "./ABDKMath64x64.sol";
import "./SqrtMath.sol";
import "./TransferHelper.sol";

/// @title Fee model for Dyson pair
contract FeeModel {
    using ABDKMath64x64 for *;

    uint internal constant MAX_FEE_RATIO = 2**64;

    /// @dev Fee ratio of token0. Max fee ratio is MAX_FEE_RATIO
    uint64 internal feeRatio0;
    /// @dev Fee ratio of token1. Max fee ratio is MAX_FEE_RATIO
    uint64 internal feeRatio1;
    /// @dev Timestamp when fee ratio of token0 last updated
    uint64 internal lastUpdateTime0;
    /// @dev Timestamp when fee ratio of token1 last updated
    uint64 internal lastUpdateTime1;
    uint64 public halfLife = 720; // Fee /= 2 every 12 minutes

    /// @dev Convenience function to get the stored fee ratio and last update time of token0 and token1
    /// @return _feeRatio0 Stored fee ratio of token0
    /// @return _feeRatio1 Stored fee ratio of token1
    /// @return _lastUpdateTime0 Stored last update time of token0
    /// @return _lastUpdateTime1 Stored last update time of token1
    function _getFeeRatioStored() internal view returns (uint64 _feeRatio0, uint64 _feeRatio1, uint64 _lastUpdateTime0, uint64 _lastUpdateTime1) {
        _feeRatio0 = feeRatio0;
        _feeRatio1 = feeRatio1;
        _lastUpdateTime0 = lastUpdateTime0;
        _lastUpdateTime1 = lastUpdateTime1;
    }

    /// @dev Pure function to calculate new fee ratio when fee ratio increased
    /// Formula shown as below with a as fee ratio before and b as fee ratio added:
    /// 1 - (1 - a)(1 - b) = a + b - ab
    /// new = before + added - before * added
    /// @param _feeRatioBefore Fee ratio before the increase
    /// @param _feeRatioAdded Fee ratio increased
    /// @return _newFeeRatio New fee ratio
    function _calcFeeRatioAdded(uint64 _feeRatioBefore, uint64 _feeRatioAdded) internal pure returns (uint64 _newFeeRatio) {
        uint before = uint(_feeRatioBefore);
        uint added = uint(_feeRatioAdded);
        _newFeeRatio = uint64(before + added - before * added / MAX_FEE_RATIO);
    }

    /// @dev Update fee ratio and last update timestamp of token0
    /// @param _feeRatioBefore Fee ratio before the increase
    /// @param _feeRatioAdded Fee ratio increased
    function _updateFeeRatio0(uint64 _feeRatioBefore, uint64 _feeRatioAdded) internal {
        feeRatio0 = _calcFeeRatioAdded(_feeRatioBefore, _feeRatioAdded);
        lastUpdateTime0 = uint64(block.timestamp);
    }

    /// @dev Update fee ratio and last update timestamp of token1
    /// @param _feeRatioBefore Fee ratio before the increase
    /// @param _feeRatioAdded Fee ratio increased
    function _updateFeeRatio1(uint64 _feeRatioBefore, uint64 _feeRatioAdded) internal {
        feeRatio1 = _calcFeeRatioAdded(_feeRatioBefore, _feeRatioAdded);
        lastUpdateTime1 = uint64(block.timestamp);
    }

    /// @notice Fee ratio halve every `halfLife` seconds
    /// @dev Calculate new fee ratio as time elapsed
    /// newFeeRatio = oldFeeRatio / 2^(elapsedTime / halfLife)
    /// @param _oldFeeRatio Fee ratio from last update
    /// @param _elapsedTime Time since last update
    /// @return _newFeeRatio New fee ratio
    function calcNewFeeRatio(uint64 _oldFeeRatio, uint _elapsedTime) public view returns (uint64 _newFeeRatio) {
        int128 t = _elapsedTime.divu(halfLife);
        int128 r = (-t).exp_2();
        _newFeeRatio = uint64(r.mulu(uint(_oldFeeRatio)));
    }

    /// @notice The fee ratios returned are the stored fee ratios with halving applied
    /// @return _feeRatio0 Fee ratio of token0 after halving update
    /// @return _feeRatio1 Fee ratio of token1 after halving update
    function getFeeRatio() public view returns (uint64 _feeRatio0, uint64 _feeRatio1) {
        uint64 _lastUpdateTime0;
        uint64 _lastUpdateTime1;
        (_feeRatio0, _feeRatio1, _lastUpdateTime0, _lastUpdateTime1) = _getFeeRatioStored();
        _feeRatio0 = calcNewFeeRatio(_feeRatio0, block.timestamp - uint(_lastUpdateTime0));
        _feeRatio1 = calcNewFeeRatio(_feeRatio1, block.timestamp - uint(_lastUpdateTime1));
    }
}

/// @title Contract with basic swap logic and fee mechanism
contract Feeswap is FeeModel {
    using TransferHelper for address;

    address public token0;
    address public token1;
    /// @notice Fee recipient
    address public feeTo;
    /// @dev Used to keep track of fee earned to save gas by not transferring fee away everytime.
    /// Need to discount this amount when calculating reserve
    uint internal accumulatedFee0;
    uint internal accumulatedFee1;

    /// @dev Mutex to prevent re-entrancy
    uint private unlocked = 1;

    event Swap(address indexed sender, bool indexed isSwap0, uint amountIn, uint amountOut, address indexed to);
    event FeeCollected(uint token0Amt, uint token1Amt);

    modifier lock() {
        require(unlocked == 1, 'LOCKED');
        unlocked = 0;
        _;
        unlocked = 1;
    }

    function initialize(address _token0, address _token1) public virtual {
        require(token0 == address(0), 'FORBIDDEN');
        token0 = _token0;
        token1 = _token1;
    }

    function getReserves() public view returns (uint reserve0, uint reserve1) {
        reserve0 = IERC20(token0).balanceOf(address(this)) - accumulatedFee0;
        reserve1 = IERC20(token1).balanceOf(address(this)) - accumulatedFee1;
    }

    /// @param input Amount of token0 to swap
    /// @param minOutput Minimum amount of token1 expected to receive
    /// @return fee Amount of token0 as fee
    /// @return output Amount of token1 swapped
    function _swap0in(uint input, uint minOutput) internal returns (uint fee, uint output) {
        require(input > 0, "INVALID_INPUT_AMOUNT");
        (uint reserve0, uint reserve1) = getReserves();
        (uint64 _feeRatio0, uint64 _feeRatio1) = getFeeRatio();
        fee = uint(_feeRatio0) * input / MAX_FEE_RATIO;
        uint inputLessFee = input - fee;
        output = inputLessFee * reserve1 / (reserve0 + inputLessFee);
        require(output >= minOutput, "SLIPPAGE");
        uint64 feeRatioAdded = uint64(output * MAX_FEE_RATIO / reserve1);
        _updateFeeRatio1(_feeRatio1, feeRatioAdded);
    }

    /// @param input Amount of token1 to swap
    /// @param minOutput Minimum amount of token0 expected to receive
    /// @return fee Amount of token1 as fee
    /// @return output Amount of token0 swapped
    function _swap1in(uint input, uint minOutput) internal returns (uint fee, uint output) {
        require(input > 0, "INVALID_INPUT_AMOUNT");
        (uint reserve0, uint reserve1) = getReserves();
        (uint64 _feeRatio0, uint64 _feeRatio1) = getFeeRatio();
        fee = uint(_feeRatio1) * input / MAX_FEE_RATIO;
        uint inputLessFee = input - fee;
        output = inputLessFee * reserve0 / (reserve1 + inputLessFee);
        require(output >= minOutput, "SLIPPAGE");
        uint64 feeRatioAdded = uint64(output * MAX_FEE_RATIO / reserve0);
        _updateFeeRatio0(_feeRatio0, feeRatioAdded);
    }

    /// @notice Perfrom swap from token0 to token1
    /// Half of the swap fee goes to `feeTo` if `feeTo` is set
    /// @dev Re-entrancy protected
    /// @param to Address that receives swapped token1
    /// @param input Amount of token0 to swap
    /// @param minOutput Minimum amount of token1 expected to receive
    /// @return output Amount of token1 swapped
    function swap0in(address to, uint input, uint minOutput) external lock returns (uint output) {
        uint fee;
        (fee, output) = _swap0in(input, minOutput);
        token0.safeTransferFrom(msg.sender, address(this), input);
        token1.safeTransfer(to, output);
        if(feeTo != address(0)) accumulatedFee0 += fee / 2;
        emit Swap(msg.sender, true, input, output, to);
    }

    /// @notice Perfrom swap from token1 to token0
    /// Half of the swap fee goes to `feeTo` if `feeTo` is set
    /// @dev Re-entrancy protected
    /// @param to Address that receives swapped token0
    /// @param input Amount of token1 to swap
    /// @param minOutput Minimum amount of token0 expected to receive
    /// @return output Amount of token0 swapped
    function swap1in(address to, uint input, uint minOutput) external lock returns (uint output) {
        uint fee;
        (fee, output) = _swap1in(input, minOutput);
        token1.safeTransferFrom(msg.sender, address(this), input);
        token0.safeTransfer(to, output);
        if(feeTo != address(0)) accumulatedFee1 += fee / 2;
        emit Swap(msg.sender, false, input, output, to);
    }

    function collectFee() public lock {
        uint f0 = accumulatedFee0;
        uint f1 = accumulatedFee1;
        accumulatedFee0 = 0;
        accumulatedFee1 = 0;
        token0.safeTransfer(feeTo, f0);
        token1.safeTransfer(feeTo, f1);
        emit FeeCollected(f0, f1);
    }
}

/// @title Dyson pair contract
contract DysonPair is Feeswap {
    using SqrtMath for *;
    using TransferHelper for address;

    /// @dev Square root of `MAX_FEE_RATIO`
    uint private constant MAX_FEE_RATIO_SQRT = 2**32;
    /// @dev Beware that fee ratio and premium base unit are different
    uint private constant PREMIUM_BASE_UNIT = 1e18;
    /// @dev For EIP712
    bytes32 public immutable DOMAIN_SEPARATOR;
    bytes32 public constant WITHDRAW_TYPEHASH = keccak256("withdraw(address operator,uint index,address to,uint deadline)");

    /// @notice A note records the amount of token0 or token1 user gets when the user redeem the note
    /// and the timestamp when user can redeem.
    /// The amount of token0 and token1 include the premium
    struct Note {
        uint token0Amt;
        uint token1Amt;
        uint due;
    }

    /// @dev Factory of this contract
    address public factory;
    IFarm public farm;

    /// @notice Volatility which affects premium and can be set by governance, i.e. controller of factory contract
    uint public basis = 0.7e18;

    /// @notice Total number of notes created by user
    mapping(address => uint) public noteCount;
    /// @notice Notes created by user, indexed by note number
    mapping(address => mapping(uint => Note)) public notes;

    event Deposit(address indexed user, bool indexed isToken0, uint index, uint amountIn, uint token0Amt, uint token1Amt, uint due);
    event Withdraw(address indexed user, bool indexed isToken0, uint index, uint amountOut);

    constructor() {
        uint chainId;
        assembly {
            chainId := chainid()
        }
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'),
                keccak256(bytes("DysonPair")),
                keccak256(bytes('1')),
                chainId,
                address(this)
            )
        );
    }

    /// @notice Premium = volatility * sqrt(time / 365 days) * 0.4
    /// @dev sqrt(time / 365 days) is pre-calculated to save gas.
    /// Note that premium could be larger than `PREMIUM_BASE_UNIT`
    /// @param time Lock time. It can be either 1 day, 3 days, 7 days or 30 days
    /// @return premium Premium
    function getPremium(uint time) public view returns (uint premium) {
        if(time == 1 days) premium = basis * 20936956903608548 / PREMIUM_BASE_UNIT;
        else if(time == 3 days) premium = basis * 36263873112929960 / PREMIUM_BASE_UNIT;
        else if(time == 7 days) premium = basis * 55393981177425144 / PREMIUM_BASE_UNIT;
        else if(time == 30 days) premium = basis * 114676435816199168 / PREMIUM_BASE_UNIT;
        else revert("INVALID_TIME");
    }

    function initialize(address _token0, address _token1) public override {
        super.initialize(_token0, _token1);
        factory = msg.sender;
    }

    /// @notice `basis` can only be set by governance, i.e., controller of factory contract
    function setBasis(uint _basis) external lock {
        require(IDysonFactory(factory).controller() == msg.sender, "FORBIDDEN");
        basis = _basis;
    }

    /// @notice `halfLife` can only be set by governance, i.e., controller of factory contract
    function setHalfLife(uint64 _halfLife) external lock {
        require(IDysonFactory(factory).controller() == msg.sender, "FORBIDDEN");
        require( _halfLife > 0, "HALF_LIFE_CANNOT_BE_ZERO");
        halfLife = _halfLife;
    }

    /// @notice `farm` can only be set by governance, i.e., controller of factory contract
    function setFarm(address _farm) external lock {
        require(IDysonFactory(factory).controller() == msg.sender, "FORBIDDEN");
        farm = IFarm(_farm);
    }

    /// @notice `feeTo` can only be set by governance, i.e., controller of factory contract
    function setFeeTo(address _feeTo) external lock {
        require(IDysonFactory(factory).controller() == msg.sender, "FORBIDDEN");
        if(feeTo != address(0)) collectFee();
        feeTo = _feeTo;
    }

    /// @notice rescue token stucked in this contract
    /// @param tokenAddress Address of token to be rescued
    /// @param to Address that will receive token
    /// @param amount Amount of token to be rescued
    function rescueERC20(address tokenAddress, address to, uint256 amount) external {
        require(IDysonFactory(factory).controller() == msg.sender, "FORBIDDEN");
        require(tokenAddress != token0);
        require(tokenAddress != token1);
        tokenAddress.safeTransfer(to, amount);
    }

    function _addNote(address to, bool depositToken0, uint token0Amt, uint token1Amt, uint time, uint premium) internal {
        uint index = noteCount[to]++;
        Note storage note = notes[to][index];

        uint inputAmt = depositToken0 ? token0Amt : token1Amt;
        uint token0AmtWithPremium = token0Amt * (premium + PREMIUM_BASE_UNIT) / PREMIUM_BASE_UNIT;
        uint token1AmtWithPremium = token1Amt * (premium + PREMIUM_BASE_UNIT) / PREMIUM_BASE_UNIT;
        uint dueTime = block.timestamp + time;

        note.token0Amt = token0AmtWithPremium;
        note.token1Amt = token1AmtWithPremium;
        note.due = dueTime;

        emit Deposit(to, depositToken0, index, inputAmt, token0AmtWithPremium, token1AmtWithPremium, dueTime);
    }

    function _grantAP(address to, uint input, uint output, uint premium) internal {
        if(address(farm) != address(0)) {
            uint ap = (input * output).sqrt() * premium / PREMIUM_BASE_UNIT;
            farm.grantAP(to, ap);
        }
    }

    /// @notice User deposit token0. This function simulates it as `swap0in`
    /// but only charges fee base on the fee computed and does not perform actual swap.
    /// Half of the swap fee goes to `feeTo` if `feeTo` is set.
    /// If `farm` is set, this function also computes the amount of AP for the user and calls `farm.grantAP()`.
    /// The amount of AP = sqrt(input * output) * (preium / PREMIUM_BASE_UNIT)
    /// @dev Re-entrancy protected
    /// @param to Address that owns the note
    /// @param input Amount of token0 to deposit
    /// @param minOutput Minimum amount of token1 expected to receive if the swap is perfromed
    /// @param time Lock time
    /// @return output Amount of token1 received if the swap is performed
    function deposit0(address to, uint input, uint minOutput, uint time) external lock returns (uint output) {
        require(to != address(0), "TO_CANNOT_BE_ZERO");
        uint fee;
        (fee, output) = _swap0in(input, minOutput);
        uint premium = getPremium(time);

        _addNote(to, true, input, output, time, premium);

        token0.safeTransferFrom(msg.sender, address(this), input);
        if(feeTo != address(0)) accumulatedFee0 += fee / 2;
        _grantAP(to, input, output, premium);
    }

    /// @notice User deposit token1. This function simulates it as `swap1in`
    /// but only charges fee base on the fee computed and does not perform actual swap.
    /// Half of the swap fee goes to `feeTo` if `feeTo` is set.
    /// If `farm` is set, this function also computes the amount of AP for the user and calls `farm.grantAP()`.
    /// The amount of AP = sqrt(input * output) * (preium / PREMIUM_BASE_UNIT)
    /// @dev Re-entrancy protected
    /// @param to Address that owns the note
    /// @param input Amount of token1 to deposit
    /// @param minOutput Minimum amount of token0 expected to receive if the swap is perfromed
    /// @param time Lock time
    /// @return output Amount of token0 received if the swap is performed
    function deposit1(address to, uint input, uint minOutput, uint time) external lock returns (uint output) {
        require(to != address(0), "TO_CANNOT_BE_ZERO");
        uint fee;
        (fee, output) = _swap1in(input, minOutput);
        uint premium = getPremium(time);

        _addNote(to, false, output, input, time, premium);

        token1.safeTransferFrom(msg.sender, address(this), input);
        if(feeTo != address(0)) accumulatedFee1 += fee / 2;
        _grantAP(to, input, output, premium);
    }

    /// @notice When withdrawing, the token to be withdrawn is the one with less impact on the pool if withdrawn
    /// Strike price: `token1Amt` / `token0Amt`
    /// Market price: (reserve1 * sqrt(1 - feeRatio0)) / (reserve0 * sqrt(1 - feeRatio1))
    /// If strike price > market price, withdraw token0 to user, and token1 vice versa
    /// Formula to determine which token to withdraw:
    /// `token0Amt` * sqrt(1 - feeRatio0) / reserve0 < `token1Amt` * sqrt(1 - feeRatio1) / reserve1
    /// @dev Formula can be transformed to:
    /// sqrt((1 - feeRatio0)/(1 - feeRatio1)) * `token0Amt` / reserve0 < `token1Amt` / reserve1
    /// @dev Content of withdrawn note will be cleared
    /// @param from Address of the user withdrawing
    /// @param index Index of the note
    /// @param to Address to receive the redeemed token0 or token1
    /// @return token0Amt Amount of token0 withdrawn
    /// @return token1Amt Amount of token1 withdrawn
    function _withdraw(address from, uint index, address to) internal returns (uint token0Amt, uint token1Amt) {
        Note storage note = notes[from][index];
        require(note.due > 0, "INVALID_NOTE");
        require(note.due <= block.timestamp, "EARLY_WITHDRAWAL");
        (uint reserve0, uint reserve1) = getReserves();
        (uint64 _feeRatio0, uint64 _feeRatio1) = getFeeRatio();

        if((MAX_FEE_RATIO * (MAX_FEE_RATIO - uint(_feeRatio0)) / (MAX_FEE_RATIO - uint(_feeRatio1))).sqrt() * note.token0Amt / reserve0 < MAX_FEE_RATIO_SQRT * note.token1Amt / reserve1) {
            token0Amt = note.token0Amt;
            token0.safeTransfer(to, note.token0Amt);
            uint64 feeRatioAdded = uint64(note.token0Amt * MAX_FEE_RATIO / reserve0);
            _updateFeeRatio0(_feeRatio0, feeRatioAdded);
            emit Withdraw(from, true, index, note.token0Amt);
        }
        else {
            token1Amt = note.token1Amt;
            token1.safeTransfer(to, note.token1Amt);
            uint64 feeRatioAdded = uint64(note.token1Amt * MAX_FEE_RATIO / reserve1);
            _updateFeeRatio1(_feeRatio1, feeRatioAdded);
            emit Withdraw(from, false, index, note.token1Amt);
        }
        note.token0Amt = 0;
        note.token1Amt = 0;
        note.due = 0;
    }

    /// @notice Withdraw the note and receive either one of token0 or token1
    /// @dev Re-entrancy protected
    /// @param index Index of the note owned by user
    /// @return token0Amt Amount of token0 withdrawn
    /// @return token1Amt Amount of token1 withdrawn
    function withdraw(uint index) external lock returns (uint token0Amt, uint token1Amt) {
        return _withdraw(msg.sender, index, msg.sender);
    }

    /// @notice Withdraw the note and receive either one of token0 or token1.
    /// User must also sign over the address calling this function
    /// @dev Re-entrancy protected
    /// @param from Address of the user withdrawing
    /// @param index Index of the note
    /// @param to Address to receive the redeemed token0 or token1
    /// @param deadline deadline
    /// @param sig signature
    /// @return token0Amt Amount of token0 withdrawn
    /// @return token1Amt Amount of token1 withdrawn
    function withdrawWithSig(address from, uint index, address to, uint deadline, bytes calldata sig) external lock returns (uint token0Amt, uint token1Amt) {
        require(block.timestamp <= deadline || deadline == 0, "EXCEED_DEADLINE");
        require(from != address(0), "FROM_CANNOT_BE_ZERO");
        bytes32 structHash = keccak256(abi.encodePacked(WITHDRAW_TYPEHASH, msg.sender, index, to, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));
        require(from == _ecrecover(digest, sig), "INVALID_SIGNATURE");
        return _withdraw(from, index, to);
    }

    function _ecrecover(bytes32 hash, bytes memory signature) internal pure returns (address) {
        if (signature.length == 65) {
            bytes32 r;
            bytes32 s;
            uint8 v;
            assembly {
                r := mload(add(signature, 0x20))
                s := mload(add(signature, 0x40))
                v := byte(0, mload(add(signature, 0x60)))
            }

            if (uint256(s) > 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0) {
                return address(0);
            } else if (v != 27 && v != 28) {
                return address(0);
            } else {
                return ecrecover(hash, v, r, s);
            }
        } else {
            return address(0);
        }
    }
}
