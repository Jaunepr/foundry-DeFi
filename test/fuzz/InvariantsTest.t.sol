//SPDX-License-Identifier:MIT
pragma solidity ^0.8.23;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoins} from "../../src/DecentralizedStableCoins.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Handler} from "./Handler.t.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";

contract InvariantsTest is StdInvariant, Test {
    DeployDSC deployer;
    DSCEngine dsce;
    DecentralizedStableCoins dsc;
    HelperConfig config;

    address weth;
    address wbtc;

    Handler handler;

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (,, weth, wbtc,) = config.activeNetWorkConfig();
        // targetContract(address(dsce));
        handler = new Handler(dsce, dsc);
        targetContract(address(handler)); // For dont call redeem collateral function before deposite them
    }

    // This function calls every functions of your contract to break the assert in this test
    function invariant_MustHaveMoreValueThanTotalSupply() public view {
        // get the value of all the collateral in the protocol and compare it to all the debt (dsc)
        uint256 totalSupply = dsc.totalSupply();
        uint256 wethDeposited = ERC20Mock(weth).balanceOf(address(dsce));
        uint256 wbtcDeposited = ERC20Mock(wbtc).balanceOf(address(dsce));

        uint256 wethValue = dsce.getUsdValue(weth, wethDeposited);
        uint256 wbtcValue = dsce.getUsdValue(wbtc, wbtcDeposited);

        console.log("weth value: ", wethValue);
        console.log("wbtc value: ", wbtcValue);
        console.log("total supply: ", totalSupply);
        console.log("Times mint called:", handler.timesMintIsCalled());

        assert(wethValue + wbtcValue >= totalSupply);
    }

    function invariant_gettersShouldNotRevert() public view {
        dsce.getPrecision();
        dsce.getLiquidationBonus();
        // all getter functions ...
        // forge inspect CONTRACT(DSCEngine) methods   -> output all functions &args &selectors
    }
}
