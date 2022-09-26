// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Script.sol";

contract Addresses is Script {
    string file;

    /// @dev Read from config file. Need to set read permission for the config file in foundry.toml
    /// Config file is a JSON file and value is accessed by `vm.parseJson(file, ".lv1Key.lv2Key")`
    /// For example, to access WETH address in Mainnet: `vm.parseJson(file, `.mainnet.WETH`)`
    /// @param addrId Identifier for the address, e.g., "WETH"
    function getAddress(string memory addrId) internal returns (address) {
        file = vm.readFile("deploy-config.json");

        string memory key;
        if (block.chainid == 1) {
            // Mainnet
            key = string.concat(".mainnet.", addrId);
        } else if (block.chainid == 5) {
            // Goerli
            key = string.concat(".goerli.", addrId);
        } else {
            // Default to local testnet
            key = string.concat(".local.", addrId);
        }
        bytes memory data = vm.parseJson(file, key);
        address addr = abi.decode(data, (address));
        return addr;
    }
}