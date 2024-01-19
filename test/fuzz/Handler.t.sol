// SPDX-License-Identifier:MIT
pragma solidity ^0.8.23;

import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoins} from "../../src/DecentralizedStableCoins.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract Handler is Test {
    DSCEngine dsce;
    DecentralizedStableCoins dsc;

    // Ghost Variables
    uint96 public constant MAX_DEPOSIT_SIZE = type(uint96).max;

    ERC20Mock public weth;
    ERC20Mock public wbtc;

    uint256 public timesMintIsCalled;
    address[] public usersWithCollateralDeposited;
    MockV3Aggregator public ethUsdPriceFeed;
    MockV3Aggregator public btcUsdPriceFeed;

    constructor(DSCEngine _dscEngine, DecentralizedStableCoins _dsc) {
        dsce = _dscEngine;
        dsc = _dsc;
        address[] memory tokens = dsce.getCollateralTokens();
        weth = ERC20Mock(tokens[0]);
        wbtc = ERC20Mock(tokens[1]);

        ethUsdPriceFeed = MockV3Aggregator(dsce.getCollateralTokenPriceFeed(address(weth)));
        btcUsdPriceFeed = MockV3Aggregator(dsce.getCollateralTokenPriceFeed(address(wbtc)));
    }

    function mintDsc(uint256 amountDscToMInt, uint256 addressSeed) public {
        if (usersWithCollateralDeposited.length == 0) {
            return;
        }
        address sender = usersWithCollateralDeposited[addressSeed % usersWithCollateralDeposited.length];

        (uint256 totalDscMinted, uint256 totalCollateralValueInUsd) = dsce.getAccountInformation(sender);
        // dont < 0
        int256 maxDscToMinted = (int256(totalCollateralValueInUsd) / 2) - int256(totalDscMinted);
        if (maxDscToMinted < 0) {
            return;
        }
        amountDscToMInt = bound(amountDscToMInt, 0, uint256(maxDscToMinted));
        if (amountDscToMInt == 0) {
            return;
        }
        // console.log("amountDscToMInt = ", amountDscToMInt);
        vm.startPrank(sender);
        dsce.mintDsc(amountDscToMInt);
        vm.stopPrank();
        timesMintIsCalled++;
    }

    // redeem collateral
    function depositeCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);

        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(dsce), amountCollateral);
        dsce.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
        usersWithCollateralDeposited.push(msg.sender); // ignore double push right now
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        uint256 maxCollateralToRedeem = dsce.getUserCollateralAmount(msg.sender, address(collateral));
        amountCollateral = bound(amountCollateral, 0, maxCollateralToRedeem);
        if (amountCollateral == 0) {
            return;
        }
        dsce.redeemCollateral(address(collateral), amountCollateral);
    }

    // function updateCollateralPrice(uint256 newPrice) public {
    //     int256 newPriceInt = int256(newPrice);
    //     ethUsdPriceFeed.updateAnswer(newPriceInt);
    // }

    // helper
    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth;
        } else {
            return wbtc;
        }
    }
}
