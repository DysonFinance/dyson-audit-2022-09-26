pragma solidity >=0.8.0;

// SPDX-License-Identifier: MIT

interface IGauge {
    function bonus(address) external view returns (uint);
    function nextRewardRate() external view returns (uint);
    function weight() external view returns (uint);
    function balanceOfAt(address account, uint week) external view returns (uint);
    function totalSupplyAt(uint week) external view returns (uint);
    function genesis() external view returns (uint);
}