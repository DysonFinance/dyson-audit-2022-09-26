pragma solidity 0.8.17;

// SPDX-License-Identifier: AGPL-3.0

import "./DysonPair.sol";

contract DysonFactory {
    address public controller;
    address public pendingController;
    bool public permissionless;

    mapping(address => mapping(address => uint)) public getPairCount;
    mapping(address => mapping(address => mapping(uint => address))) public getPair;
    address[] public allPairs;

    event PairCreated(address indexed token0, address indexed token1, uint id, address pair, uint);

    constructor(address _controller) {
        controller = _controller;
    }

    function allPairsLength() external view returns (uint) {
        return allPairs.length;
    }

    function createPair(address tokenA, address tokenB) external returns (address pair) {
        require(permissionless || msg.sender == controller, 'FORBIDDEN');
        require(tokenA != tokenB, 'IDENTICAL_ADDRESSES');
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'ZERO_ADDRESS');
        uint id = ++getPairCount[token0][token1];
        bytes32 salt = keccak256(abi.encodePacked(token0, token1, id));
        pair = address(new DysonPair{salt : salt}());
        DysonPair(pair).initialize(token0, token1);
        getPair[token0][token1][id - 1] = pair;
        allPairs.push(pair);
        emit PairCreated(token0, token1, id, pair, allPairs.length);
    }

    function setController(address _controller) external {
        require(msg.sender == controller, 'FORBIDDEN');
        pendingController = _controller;
    }

    function becomeController() external {
        require(msg.sender == pendingController, 'FORBIDDEN');
        pendingController = address(0);
        controller = msg.sender;
    }

    function open2public() external {
        require(msg.sender == controller, 'FORBIDDEN');
        permissionless = true;
    }
}
