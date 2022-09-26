pragma solidity >=0.8.0;

// SPDX-License-Identifier: MIT

interface IERC20Mintable {
    function mint(address to, uint amount) external returns (bool);
}