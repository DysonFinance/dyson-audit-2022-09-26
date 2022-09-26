pragma solidity >=0.8.0;

// SPDX-License-Identifier: MIT

import "src/interfaces/IERC20.sol";

interface IDyson is IERC20 {
    function addMinter(address) external;
    function removeMinter(address) external;
}