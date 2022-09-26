pragma solidity 0.8.17;

// SPDX-License-Identifier: AGPL-3.0

import "./Agency.sol";
import "./DysonFactory.sol";
import "./Dyson.sol";
import "./sDYSON.sol";
import "./DysonRouter.sol";
import "./Farm.sol";

contract Deploy {
    Agency public agency;
    DysonFactory public factory;
    DYSON public dyson;
    sDYSON public sdyson;
    DysonRouter public router;
    StakingRateModel public rateModel;
    Farm public farm;

    constructor(address owner, address root, address weth) {
        agency = new Agency(owner, root);
        factory = new DysonFactory(owner);
        router = new DysonRouter(weth, owner);
        dyson = new DYSON(owner);
        rateModel = new StakingRateModel(0.0625e18);
        sdyson = new sDYSON(address(this), address(dyson));
        sdyson.setStakingRateModel(address(rateModel));
        sdyson.transferOwnership(owner);
        farm = new Farm(owner, address(agency), address(dyson));
    }
}