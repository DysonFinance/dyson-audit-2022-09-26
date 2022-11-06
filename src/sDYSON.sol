pragma solidity 0.8.17;

// SPDX-License-Identifier: AGPL-3.0

import "./ABDKMath64x64.sol";
import "./TransferHelper.sol";

contract StakingRateModel {
    using ABDKMath64x64 for *;

    uint public immutable initialTime;
    uint public immutable initialRate;

    /// @dev `_initialRate` is the expected initial rate divided by 16
    /// For example, if expected initial rate is 1, i.e., STAKING_RATE_BASE_UNIT
    /// then `_initialRate` passed in would be STAKING_RATE_BASE_UNIT / 16
    constructor(uint _initialRate) {
        initialTime = block.timestamp;
        initialRate = _initialRate;
    }

    /// @notice Base on `lockDuration` plus time since inital time, calculate the expected staking rate.
    /// Note that `lockDuration` must be greater than 30 minutes and less and 4 years (1 year = 365.25 days)
    /// Formula to calculate staking rate:
    /// `initialRate` * 2^((`lockDuration` + time_since_initial_time) / 1 year)
    /// @param lockDuration Duration to lock Dyson
    /// @return rate Staking rate
    function stakingRate(uint lockDuration) external view returns (uint rate) {
        if(lockDuration < 30 minutes) return 0;
        if(lockDuration > 1461 days) return 0;
        lockDuration = lockDuration + block.timestamp - initialTime;

        int128 lockPeriod = lockDuration.divu(365.25 days);
        int128 r = lockPeriod.exp_2();
        rate = r.mulu(initialRate);
    }
}

interface IsDYSONUpgradeReceiver {
    function onMigrationReceived(address, uint) external returns (bytes4);
}

contract sDYSON {
    using TransferHelper for address;

    struct Vault {
        uint dysonAmount;
        uint sDYSONAmount;
        uint unlockTime;
    }

    /// @dev For EIP-2612 permit
    bytes32 public immutable DOMAIN_SEPARATOR;
    /// @dev keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)")
    bytes32 public constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;
    /// @dev Max staking rate
    uint private constant STAKING_RATE_BASE_UNIT = 1e18;
    string public constant symbol = "sDYSN";
    string public constant name = "Sealed Dyson Sphere";
    uint8 public constant decimals = 18;
    address public immutable Dyson;
    /// @dev bytes4(keccak256("onMigrationReceived(address,uint256)"))
    bytes4 private constant _MIGRATE_RECEIVED = 0xc5b97e06;

    address public owner;
    /// @dev Migration contract for user to migrate to new staking contract
    address public migration;
    uint public totalSupply;

    StakingRateModel public currentModel;

    /// @notice User's sDyson amount
    mapping(address => uint) public balanceOf;
    /// @notice User's sDyson allowance for spender
    mapping(address => mapping(address => uint)) public allowance;
    /// @notice User's vault, indexed by number
    mapping(address => mapping(uint => Vault)) public vaults;
    /// @notice Number of vaults owned by user
    mapping(address => uint) public vaultCount;
    /// @notice Sum of dyson amount in all of user's current vaults
    mapping(address => uint) public dysonAmountStaked;
    /// @notice Sum of sDyson amount in all of user's current vaults
    mapping(address => uint) public votingPower;

    /// @notice User's permit nonce
    mapping(address => uint256) public nonces;

    event TransferOwnership(address newOwner);
    event Transfer(address indexed from, address indexed to, uint amount);
    event Approval(address indexed owner, address indexed spender, uint amount);
    event Stake(address indexed vaultOwner, address indexed depositor, uint amount, uint sDYSONAmount, uint time);
    event Restake(address indexed vaultOwner, uint index, uint dysonAmountAdded, uint sDysonAmountAdded, uint time);
    event Unstake(address indexed vaultOwner, address indexed receiver, uint amount, uint sDYSONAmount);
    event Migrate(address indexed vaultOwner, uint index);

    constructor(address _owner, address dyson) {
        require(_owner != address(0), "OWNER_CANNOT_BE_ZERO");
        require(dyson != address(0), "DYSON_CANNOT_BE_ZERO");
        owner = _owner;
        Dyson = dyson;

        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(name)),
                keccak256(bytes("1")),
                chainId,
                address(this)
            )
        );
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "FORBIDDEN");
        _;
    }

    function transferOwnership(address _owner) external onlyOwner {
        require(_owner != address(0), "OWNER_CANNOT_BE_ZERO");
        owner = _owner;

        emit TransferOwnership(_owner);
    }

    function approve(address spender, uint amount) external returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function _approve(
        address _owner,
        address _spender,
        uint256 _amount
    ) internal virtual {
        require(_owner != address(0), "ERC20: approve from the zero address");
        require(_spender != address(0), "ERC20: approve to the zero address");

        allowance[_owner][_spender] = _amount;
        emit Approval(_owner, _spender, _amount);
    }

    /// @dev Mint sDyson
    function _mint(address to, uint amount) internal returns (bool) {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
        return true;
    }

    /// @dev Burn sDyson
    function _burn(address from, uint amount) internal returns (bool) {
        balanceOf[from] -= amount;
        totalSupply -= amount;
        emit Transfer(from, address(0), amount);
        return true;
    }

    function _transfer(address from, address to, uint amount) internal returns (bool) {
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }

    function transfer(address to, uint amount) external returns (bool) {
        return _transfer(msg.sender, to, amount);
    }

    function transferFrom(address from, address to, uint amount) external returns (bool) {
        if (allowance[from][msg.sender] != type(uint).max) {
            allowance[from][msg.sender] -= amount;
        }
        return _transfer(from, to, amount);
    }

    /// @notice Get staking rate
    /// @param lockDuration Duration to lock Dyson
    /// @return rate Staking rate
    function getStakingRate(uint lockDuration) public view returns (uint rate) {
        return currentModel.stakingRate(lockDuration);
    }

    /// @param newModel New StakingRateModel
    function setStakingRateModel(address newModel) external onlyOwner {
        currentModel = StakingRateModel(newModel);
    }

    /// @param _migration New Migration contract
    function setMigration(address _migration) external onlyOwner {
        migration = _migration;
    }

    /// @notice Stake on behalf of `to`
    /// @param to Address that owns the new vault
    /// @param amount Amount of Dyson to stake
    /// @param lockDuration Duration to lock Dyson
    /// @return sDYSONAmount Amount of sDyson minted to `to`'s new vault
    function stake(address to, uint amount, uint lockDuration) external returns (uint sDYSONAmount) {
        Vault storage vault = vaults[to][vaultCount[to]];
        sDYSONAmount = getStakingRate(lockDuration) * amount / STAKING_RATE_BASE_UNIT;
        require(sDYSONAmount > 0, "invalid lockup");

        vault.dysonAmount = amount;
        vault.sDYSONAmount = sDYSONAmount;
        vault.unlockTime = block.timestamp + lockDuration;
        
        dysonAmountStaked[to] += amount;
        votingPower[to] += sDYSONAmount;
        vaultCount[to]++;

        _mint(to, sDYSONAmount);
        Dyson.safeTransferFrom(msg.sender, address(this), amount);

        emit Stake(to, msg.sender, amount, sDYSONAmount, lockDuration);
    }

    /// @notice Restake more Dyson to user's given vault. New unlock time must be greater than old unlock time.
    /// Note that user can restake even when the vault is unlocked
    /// @param index Index of user's vault to restake
    /// @param amount Amount of Dyson to restake
    /// @param lockDuration Duration to lock Dyson
    /// @return sDysonAmountAdded Amount of new sDyson minted to user's vault
    function restake(uint index, uint amount, uint lockDuration) external returns (uint sDysonAmountAdded) {
        require(index < vaultCount[msg.sender], "invalid index");
        Vault storage vault = vaults[msg.sender][index];
        require(vault.unlockTime < block.timestamp + lockDuration, "locked");
        uint sDysonAmountOld = vault.sDYSONAmount;
        uint sDysonAmountNew = (vault.dysonAmount + amount) * getStakingRate(lockDuration) / STAKING_RATE_BASE_UNIT;
        require(sDysonAmountNew > 0, "invalid lockup");

        sDysonAmountAdded = sDysonAmountNew - sDysonAmountOld;
        vault.dysonAmount += amount;
        vault.sDYSONAmount = sDysonAmountNew;
        vault.unlockTime = block.timestamp + lockDuration;

        dysonAmountStaked[msg.sender] += amount;
        votingPower[msg.sender] += sDysonAmountAdded;

        _mint(msg.sender, sDysonAmountAdded);
        if(amount > 0) Dyson.safeTransferFrom(msg.sender, address(this), amount);

        emit Restake(msg.sender, index, amount, sDysonAmountAdded, lockDuration);
    }

    /// @notice Unstake a given user's vault after the vault is unlocked and transfer Dyson to `to`
    /// @param to Address that will receive Dyson
    /// @param index Index of user's vault to unstake
    /// @param sDYSONAmount Amount of sDyson to unstake
    /// @return amount Amount of Dyson transferred
    function unstake(address to, uint index, uint sDYSONAmount) external returns (uint amount) {
        require(sDYSONAmount > 0, "invalid input amount");
        Vault storage vault = vaults[msg.sender][index];
        require(block.timestamp >= vault.unlockTime, "locked");
        require(sDYSONAmount <= vault.sDYSONAmount, "exceed locked amount");
        amount = sDYSONAmount * vault.dysonAmount / vault.sDYSONAmount;

        vault.dysonAmount -= amount;
        vault.sDYSONAmount -= sDYSONAmount;

        dysonAmountStaked[msg.sender] -= amount;
        votingPower[msg.sender] -= sDYSONAmount;

        _burn(msg.sender, sDYSONAmount);
        Dyson.safeTransfer(to, amount);
        
        emit Unstake(msg.sender, to, amount, sDYSONAmount);
    }

    /// @notice Migrate given user's vault to new staking contract
    /// @dev Owner must set `migration` before migrate.
    /// `migration` must implement `onMigrationReceived`
    /// @param index Index of user's vault to migrate
    function migrate(uint index) external {
        require(migration != address(0), "CANNOT MIGRATE");
        Vault storage vault = vaults[msg.sender][index];
        require(vault.unlockTime > 0, "INVALID VAULT");
        uint amount = vault.dysonAmount;
        require(IsDYSONUpgradeReceiver(migration).onMigrationReceived(msg.sender, index) == _MIGRATE_RECEIVED, "MIGRATION FAILED");
        Dyson.safeTransfer(migration, amount);
        _approve(msg.sender, migration, vault.sDYSONAmount);
        dysonAmountStaked[msg.sender] -= amount;
        votingPower[msg.sender] -= vault.sDYSONAmount;
        vault.dysonAmount = 0;
        vault.sDYSONAmount = 0;
        vault.unlockTime = 0;
        emit Migrate(msg.sender, index);
    }

    /// @notice rescue token stucked in this contract
    /// @param tokenAddress Address of token to be rescued
    /// @param to Address that will receive token
    /// @param amount Amount of token to be rescued
    function rescueERC20(address tokenAddress, address to, uint256 amount) onlyOwner external {
        require(tokenAddress != Dyson);
        tokenAddress.safeTransfer(to, amount);
    }

    /// @notice EIP-2612 permit
    function permit(
        address _owner,
        address _spender,
        uint256 _amount,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external {
        require(_owner != address(0), "zero address");
        require(block.timestamp <= _deadline || _deadline == 0, "permit is expired");
        bytes32 digest = keccak256(
            abi.encodePacked(uint16(0x1901), DOMAIN_SEPARATOR, keccak256(abi.encode(PERMIT_TYPEHASH, _owner, _spender, _amount, nonces[_owner]++, _deadline)))
        );
        require(_owner == ecrecover(digest, _v, _r, _s), "invalid signature");
        _approve(_owner, _spender, _amount);
    }
}
