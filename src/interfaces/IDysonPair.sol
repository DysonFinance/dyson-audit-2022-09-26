pragma solidity >=0.8.0;

// SPDX-License-Identifier: MIT

interface IDysonPair {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getFeeRatio() external view returns(uint64, uint64);
    function getReserves() external view returns (uint reserve0, uint reserve1);
    function deposit0(address to, uint input, uint minOutput, uint time) external returns (uint output);
    function deposit1(address to, uint input, uint minOutput, uint time) external returns (uint output);
    function swap0in(address to, uint input, uint minOutput) external returns (uint output);
    function swap1in(address to, uint input, uint minOutput) external returns (uint output);
    function withdraw(uint index) external returns (uint token0Amt, uint token1Amt);
    function withdrawWithSig(address from, uint index, address to, uint deadline, bytes calldata sig) external returns (uint token0Amt, uint token1Amt);
}