pragma solidity >=0.8.0;

// SPDX-License-Identifier: MIT

interface IDysonFactory {
    function controller() external returns (address);
    function getInitCodeHash() external view returns (bytes32);
}