pragma solidity >=0.8.0;

// SPDX-License-Identifier: MIT

interface IFarm {
    function grantAP(address to, uint amount) external;

    function setPoolRewardRate(address poolId, uint _rewardRate, uint _w) external;
}