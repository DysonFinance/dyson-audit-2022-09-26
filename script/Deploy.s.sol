// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "../src/Agency.sol";
import "../src/Dyson.sol";
import "../src/sDYSON.sol";
import "../src/DysonFactory.sol";
import "../src/DysonRouter.sol";
import "../src/Farm.sol";
import "./Addresses.sol";

contract DeployScript is Addresses, Test {
    Agency public agency;
    DYSON public dyson;
    sDYSON public sDyson;
    DysonFactory public factory;
    DysonRouter public router;
    StakingRateModel public rateModel;
    Farm public farm;

    // Configs for Agency
    address root = address(0x5566);
    // Configs for DysonRouter
    address weth = getAddress("WETH");
    // Configs for StakingRateModel
    uint initialRate = 0.0625e18;

    function run() external {
        address owner = vm.envAddress("OWNER_ADDRESS");
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy Agency
        agency = new Agency(owner, root);

        // Deploy Dyson, sDyson, DysonFactory and DysonRouter
        dyson = new DYSON(owner);
        factory = new DysonFactory(owner);
        router = new DysonRouter(weth, owner, address(factory));

        // Deploy StakingRateModel and sDyson
        rateModel = new StakingRateModel(0.0625e18);
        sDyson = new sDYSON(deployer, address(dyson));
        // Setup sDyson
        sDyson.setStakingRateModel(address(rateModel));
        sDyson.transferOwnership(owner);

        // Deploy Farm
        farm = new Farm(owner, address(agency), address(dyson));

        vm.stopBroadcast();
    }
}
