//SPDX-License-Identifier:MIT

pragma solidity ^0.8.23;

import {Test, console} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoins} from "../../src/DecentralizedStableCoins.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract DSCEngineTest is Test {
    DeployDSC public deployer;
    DecentralizedStableCoins public dsc;
    DSCEngine public engine;
    HelperConfig public helperConfig;

    address wethUsdPriceFeed;
    address wbtcUsdPriceFeed;
    address weth;
    address wbtc;
    uint256 deployerKey;

    address public USER = makeAddr("Jaunepr");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether; // = $20,000
    uint256 public constant STARTING_USER_BALANCE = 10 ether;
    uint256 public constant MINTED_DSC_AMOUNT = 5 ether;
    uint256 public constant MIN_HEALTH_FACTOR = 1e18;
    uint256 public constant LIQUIDATION_THRESHOLD = 50;

    // Liquidation
    address public liquidator = makeAddr("liquidator");
    uint256 public collateralToCover = 30 ether;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, engine, helperConfig) = deployer.run();
        (wethUsdPriceFeed, wbtcUsdPriceFeed, weth,,) = helperConfig.activeNetWorkConfig();
        ERC20Mock(weth).mint(USER, STARTING_USER_BALANCE);
    }

    //////////////////////////
    // constructor Tests    //
    //////////////////////////

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertTokenAddressesLengthMatchPirceFeedAddresses() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(wethUsdPriceFeed);
        priceFeedAddresses.push(wbtcUsdPriceFeed);
        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    /////////////////////////
    // pricefeed tests    ///
    /////////////////////////

    function testGetUsdValue() public {
        uint256 ethAmount = 15e18;
        // 15e18ETH *2000/ETH = $30,000e18
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = engine.getUsdValue(weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function testGetTokenAmountFromUsd() public {
        uint256 usdAmount = 100 ether;
        // 100e18$ / 2000$/ETH = 0.05e18ETH
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = engine.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedWeth, actualWeth);
    }

    /////////////////////////
    // depositeCollateral tests    ///
    /////////////////////////

    function testRevertsIfTransferFromFails() public {}

    function testDepositeCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL); //tokenAddress(collateral) give permission to engineAddress

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.depositCollateral(weth, 0); //谁给谁转钱？ tokenAddress 转给 Engineaddress
        vm.stopPrank();
    }

    function testRevertIfIsNotAllowedToken() public {
        ERC20Mock randomToken = new ERC20Mock("RANDOM", "RAN", USER, STARTING_USER_BALANCE);
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.ESCEngine__NotAllowedToken.selector);
        engine.depositCollateral(address(randomToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    modifier depositeCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testDepositeCollateralAndGetAccountInfo() public depositeCollateral {
        (uint256 totalDscMinted, uint256 totalCollateralValueInUSD) = engine.getAccountInformation(USER);
        // 10 ether * 2000
        uint256 expectedDscMinted = 0;
        uint256 expectedCollateralValueInUSD = engine.getUsdValue(address(weth), AMOUNT_COLLATERAL);
        uint256 expectedCollateralAmount = engine.getTokenAmountFromUsd(weth, totalCollateralValueInUSD);

        assertEq(expectedCollateralValueInUSD, totalCollateralValueInUSD);
        assertEq(expectedDscMinted, totalDscMinted);
        assertEq(expectedCollateralAmount, AMOUNT_COLLATERAL);
    }

    //TODO: more tests needed by checking report.txt!! and get DSCEngine.sol test coverage above 85%!

    ///////////////////////////
    // Test MintDSC function //
    ///////////////////////////

    // Test mint DSC with zero amount
    function testMintDscZeroAmount() public {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.mintDsc(0);
        vm.stopPrank();
    }

    // Test minting DSC with a non-zero amount
    function testMintDscNonZero() public depositeCollateral {
        // Mint some DSC
        uint256 mintAmount = 5 ether; // Replace with a valid mint amount
        vm.startPrank(USER);
        engine.mintDsc(mintAmount);
        vm.stopPrank();

        // Verify that DSC was minted successfully
        uint256 totalMinted = engine.getUserDscMintedAmount(USER);
        assertEq(totalMinted, mintAmount);
    }

    ///////////////////////////////////////
    // depositCollateralAndMintDsc Tests //
    ///////////////////////////////////////

    function testRevertsIfMintedDscBreaksHealthFactor() public {
        (, int256 price,,,) = MockV3Aggregator(wethUsdPriceFeed).latestRoundData(); //get mocks price of weth
        uint256 amountToMint = AMOUNT_COLLATERAL * uint256(price) * 1e10 / 1e18; // 假设mint equals the value of the collateral
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        // uint256 expectedHealthFactor = engine.calculateHealthFactor(amountToMint, engine.getUsdValue(weth, AMOUNT_COLLATERAL));
        uint256 expectedHealthFactor = (engine.getUsdValue(weth, AMOUNT_COLLATERAL) * 50 / 100 * 1e18 / amountToMint);
        // console.log(engine.getUsdValue(weth, AMOUNT_COLLATERAL));
        // console.log(amountToMint);
        // console.log(expectedHealthFactor);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__HealthFactorBroken.selector, expectedHealthFactor));

        engine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, amountToMint);
        vm.stopPrank();
    }

    modifier depositedCollateralAndMintedDsc() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, MINTED_DSC_AMOUNT);
        vm.stopPrank();
        _;
    }

    function testCanMintWithDepositedCollateral() public depositedCollateralAndMintedDsc {
        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, MINTED_DSC_AMOUNT);
    }

    //////////////////////////////////////////////////////////
    //test mintfailed and depositecollateral transfer failed /
    //////////////////////////////////////////////////////////

    //////////////////////////////////////
    // burnDsc tests                    //
    //////////////////////////////////////

    function testBurnDscZeroAmount() public {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.burnDsc(0);
        vm.stopPrank();
    }

    //check the DSC balance after burning
    function testDscBalanceAfterBurn() public depositedCollateralAndMintedDsc {
        uint256 startingDscBalance = MINTED_DSC_AMOUNT;
        uint256 burnAmount = startingDscBalance / 2;
        vm.startPrank(USER);
        dsc.approve(address(engine), burnAmount); //这里burnDSC的是engine，授权engine对我的dsc转钱权限。
        engine.burnDsc(burnAmount);
        vm.stopPrank();
        uint256 endingDscBalance = engine.getUserDscMintedAmount(USER);
        assertEq(startingDscBalance - burnAmount, endingDscBalance);
    }

    function testCantBurnMoreDscThanBalance() public {
        vm.prank(USER);
        vm.expectRevert();
        engine.burnDsc(1);
    }

    ///////////////////////////////////
    // redeemCollateral Tests //
    //////////////////////////////////

    function testRevertsIfRedeemAmountIsZero() public depositedCollateralAndMintedDsc {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.redeemCollateral(weth, 0);
        vm.stopPrank();
    }

    function testCantRedeemMoreThanDeposite() public depositedCollateralAndMintedDsc {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        vm.expectRevert();
        engine.redeemCollateral(weth, AMOUNT_COLLATERAL + 1);
        vm.stopPrank();
    }

    function testCanRedeemCollateral() public depositeCollateral {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.redeemCollateral(weth, AMOUNT_COLLATERAL);
        assertEq(engine.getUserCollateralAmount(USER, weth), 0);
    }

    function testEmitCollateralRedeemedWithCorrectArgs() public depositeCollateral {
        vm.expectEmit(true, true, true, true);
        emit DSCEngine.CollateralRedeemed(USER, USER, weth, AMOUNT_COLLATERAL);
        vm.startPrank(USER);
        engine.redeemCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    ///////////////////////////////////
    // redeemCollateralForDsc Tests //
    //////////////////////////////////

    function testCanRedeemCollateralForDsc() public depositedCollateralAndMintedDsc {
        vm.startPrank(USER);
        // ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        dsc.approve(address(engine), MINTED_DSC_AMOUNT);
        engine.redeemCollateralForDsc(weth, AMOUNT_COLLATERAL, MINTED_DSC_AMOUNT);
        vm.stopPrank();

        assertEq(engine.getUserCollateralAmount(USER, weth), 0);
        assertEq(engine.getUserDscMintedAmount(USER), 0); //dsc.balanceOf();
    }

    ////////////////////////
    // healthFactor Tests //
    ////////////////////////
    function testCalculateHealthFactorIfDscMintedIsZero() public {
        uint256 totalDscMinted = 0;
        uint256 collateralValueInUsd = 1;
        uint256 healthFactor = type(uint256).max;
        uint256 actualHealthFactor = engine.calculateHealthFactor(totalDscMinted, collateralValueInUsd);
        assertEq(healthFactor, actualHealthFactor);
    }

    function testCalculateHealthFactor() public depositedCollateralAndMintedDsc {
        uint256 expectedHealthFactor = 2000e18;
        // weth 10 ether, DSC 5 ether, priceFeed 2000$ 10e8
        // 10e18 /2 *2000 / 5e18 = 2000
        // (, int256 price,,,) = MockV3Aggregator(wethUsdPriceFeed).latestRoundData();
        // uint256 collateralValueInUsd = (uint256(price) * 1e10 * AMOUNT_COLLATERAL) / 1e18;
        // uint256 actualHealthFactor = engine.calculateHealthFactor(MINTED_DSC_AMOUNT, collateralValueInUsd);
        uint256 actualHealthFactor = engine.getHealthFactor(USER);
        assertEq(expectedHealthFactor, actualHealthFactor);
    }

    function testHealthFactorCanGoBelowOne() public depositedCollateralAndMintedDsc {
        int256 newWethPrice = 0.5e8; //weth 1 = $0.5

        MockV3Aggregator(wethUsdPriceFeed).updateAnswer(newWethPrice);

        uint256 updateHealthFactor = engine.getHealthFactor(USER);
        assertEq(updateHealthFactor, 0.5e18);
    }

    ///////////////////////
    // Liquidation Tests //
    ///////////////////////

    function testCantLiquidateGoodHealthFactor() public depositedCollateralAndMintedDsc {
        ERC20Mock(weth).mint(liquidator, collateralToCover); //give liquidator some collateral

        vm.startPrank(liquidator);
        ERC20Mock(weth).approve(address(engine), collateralToCover);
        engine.depositCollateralAndMintDsc(weth, collateralToCover, MINTED_DSC_AMOUNT);
        dsc.approve(address(engine), MINTED_DSC_AMOUNT);
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOk.selector);
        engine.liquidate(weth, USER, MINTED_DSC_AMOUNT);
        vm.stopPrank();
    }

    modifier liquidated() {
        // arrange
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, MINTED_DSC_AMOUNT);
        vm.stopPrank();

        int256 newPrice = 0.8e8; // $2000/ETH -> $0.8/ETH
        MockV3Aggregator(wethUsdPriceFeed).updateAnswer(newPrice);
        uint256 userHealthFactor = engine.getHealthFactor(USER);
        console.log("user's new health factor", userHealthFactor); //check health factor user become bad 8ether/2/5=0.8 < 1

        ERC20Mock(weth).mint(liquidator, collateralToCover);
        console.log("liquidator's start weth balance: ", ERC20Mock(weth).balanceOf(liquidator));
        // liquidator buy 30 ether weth, pay $24
        // effert
        vm.startPrank(liquidator);
        ERC20Mock(weth).approve(address(engine), collateralToCover);
        engine.depositCollateralAndMintDsc(weth, collateralToCover, MINTED_DSC_AMOUNT);
        console.log("liquidator's balance after deposited: ", ERC20Mock(weth).balanceOf(liquidator));
        console.log("liquidator's starting DSC debt: ", engine.getUserDscMintedAmount(liquidator));
        dsc.approve(address(engine), MINTED_DSC_AMOUNT);
        engine.liquidate(weth, USER, MINTED_DSC_AMOUNT);
        console.log("liquidator's after DSC debt: ", engine.getUserDscMintedAmount(liquidator));
        console.log("USER's after DSC debt: ", engine.getUserDscMintedAmount(USER));
        console.log("liquidator's after DSC balance: ", dsc.balanceOf(liquidator));
        console.log("USER's after DSC balance: ", dsc.balanceOf(USER));
        vm.stopPrank();
        _;
    }

    function testliquidtorPayoutIsCorrect() public liquidated {
        uint256 liquidatorWethBalance = ERC20Mock(weth).balanceOf(liquidator);
        console.log("liquidator's after weth balance: ", liquidatorWethBalance);

        // 5 ether DSC == ?? WETH
        // 5 / 0.8 =6.25 ether WETH
        // 6.25 ether == $5
        // bonus = 6.25 *0.1=0.625
        // redeemAmount = 6.25+0.625 = 6.875 ether ETH = $5.5 , liquidator win $0.5!
        uint256 expectedLiquidatorWethBalance = engine.getTokenAmountFromUsd(weth, MINTED_DSC_AMOUNT)
            + (
                engine.getTokenAmountFromUsd(weth, MINTED_DSC_AMOUNT) * engine.getLiquidationBonus()
                    / engine.getLiquidationPrecision()
            );
        uint256 hardcodeBalanceOfWeth = 6.875e18;
        assertEq(liquidatorWethBalance, expectedLiquidatorWethBalance);
        assertEq(liquidatorWethBalance, hardcodeBalanceOfWeth);
    }

    ////////////////////////////
    // Tests getter functions //
    ////////////////////////////
    function testGetCollateralTokenPriceFeed() public {
        address priceFeed = engine.getTokenPriceFeed(weth);
        assertEq(priceFeed, wethUsdPriceFeed);
    }

    function testGetCollateralTokens() public {
        address[] memory collateralTokens = engine.getCollateralTokens();
        assertEq(collateralTokens[0], weth);
    }

    function testGetMinHealthFactor() public {
        uint256 minHealthFactor = engine.getMinimumHealthFactor();
        assertEq(minHealthFactor, MIN_HEALTH_FACTOR);
    }

    function testGetLiquidationThreshold() public {
        uint256 liquidationThreshold = engine.getLiquidationThreshold();
        assertEq(liquidationThreshold, LIQUIDATION_THRESHOLD);
    }

    function testGetAccountCollateralValueFromInformation() public depositeCollateral {
        (, uint256 collateralValue) = engine.getAccountInformation(USER);
        uint256 expectedCollateralValue = engine.getUsdValue(weth, AMOUNT_COLLATERAL);
        assertEq(collateralValue, expectedCollateralValue);
    }

    function testGetCollateralBalanceOfUser() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        uint256 collateralBalance = engine.getUserCollateralAmount(USER, weth);
        assertEq(collateralBalance, AMOUNT_COLLATERAL);
    }

    function testGetAccountCollateralValue() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        uint256 collateralValue = engine.getAccountCollateralValue(USER);
        uint256 expectedCollateralValue = engine.getUsdValue(weth, AMOUNT_COLLATERAL);
        assertEq(collateralValue, expectedCollateralValue);
    }

    function testGetDsc() public {
        address dscAddress = engine.getDsc();
        assertEq(dscAddress, address(dsc));
    }

    function testLiquidationPrecision() public {
        uint256 expectedLiquidationPrecision = 100;
        uint256 actualLiquidationPrecision = engine.getLiquidationPrecision();
        assertEq(actualLiquidationPrecision, expectedLiquidationPrecision);
    }
}
