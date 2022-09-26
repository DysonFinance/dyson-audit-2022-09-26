pragma solidity >=0.8.0;

// SPDX-License-Identifier: MIT

interface IAgency {
    function whois(address agent) external view returns (uint);
    function userInfo(address agent) external view returns (address ref, uint gen);
    function transfer(address from, address to, uint id) external returns (bool);
    function totalSupply() external view returns (uint);
    function getAgent(uint id) external view returns (address, uint, uint, uint, uint[] memory);
}