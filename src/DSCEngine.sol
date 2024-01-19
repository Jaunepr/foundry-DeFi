// SPDX-License-Identifier: MIT

//Layout of Contract
//version
//imports
//errors
//interface, libraries, contracts
//Type declarations
//State variables
//Events
//Modifiers
//Functions

//Layout of FUnctions:
//constructor
//receive function(if exists)
//fallback function(if exists)
//external
//public
//internal
//private
//view & pure

pragma solidity ^0.8.23;

/**
 * @title DSCEngine
 * @author Jaunepr
 *
 * The system is designed to be as minimal as possible, and have the tokens maintain a 1 token == $1 peg.
 * This stablecoin has the properties:
 * - Exogenous Collateral(外部抵押)
 * - Dollar Pegged
 * - Algorithmic stable
 *
 * It is similar to DAI if DAI had no governance(治理), no fees and was only backed(supported) bu WETH and WBTC.
 *
 * Our DSC system should always be "overcollateralized". At all time, the value of all collateral should >= the $ backed value of all the DSC
 *
 * @notice It is the core of DSC system. It handles the logic for minting and redeeming(赎回) DSC, as well as depositing(存入) & withdrawing collateral.
 * @notice This contract is VERY loosely(某种程度上的启发) based on the MakerDAO DSS (DAI) system
 */
import {DecentralizedStableCoins} from "./DecentralizedStableCoins.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {OracleLib} from "./libraries/OracleLib.sol";

contract DSCEngine is ReentrancyGuard {
    //Errors
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error ESCEngine__NotAllowedToken();
    error DSCEngine__TransferFailed();
    error DSCEngine__HealthFactorBroken(uint256 userHealthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotImprove();

    // Types
    using OracleLib for AggregatorV3Interface; // means type AggregatorV3Interface can use OracleLib library's function

    //State Variables
    uint256 private constant ADD_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    // 50/100 =0.5 means that collateral must be 200% of the DSC value
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant LIQUIDATION_BOUNS = 10;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;

    // mapping(address => bool) private s_tokenToAllowed;
    mapping(address token => address priceFeed) private s_tokenToPriceFeed;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_DscMinted;
    address[] private s_collateralToken;

    DecentralizedStableCoins private immutable i_dsc;

    //Event
    event DepositedCollateral(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(
        address indexed redeemFrom, address indexed redeemTo, address indexed token, uint256 amount
    );

    //Modifiers
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address tokenAddresses) {
        if (s_tokenToPriceFeed[tokenAddresses] == address(0)) {
            revert ESCEngine__NotAllowedToken();
        }
        _;
    }

    //Functions
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        //USD Price Feeds
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_tokenToPriceFeed[tokenAddresses[i]] = priceFeedAddresses[i]; //token => price value
            s_collateralToken.push(tokenAddresses[i]);
        }
        i_dsc = DecentralizedStableCoins(dscAddress);
    }
    ///////////////////////////
    // external functions
    ///////////////////////////

    /**
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral The amount of collateral to deposit
     * @param amountDscToMint The amount of decentralized stablecoin to mint
     * @notice This function will deposit your collateral and mint DSC in one transaction.
     */
    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }

    /*
     * follow the CEI(check, effect, interact)
     * @param tokenCollateralAddress the Address of the token to deposite as collateral
     * @param amountCollateral the amount of collateral to deposite
     * @notice we just allow collateral we allowed.
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        // ensure user's token acount-->need a mapping s_collateraldeposited
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral; //updating state so need a emit
        emit DepositedCollateral(msg.sender, tokenCollateralAddress, amountCollateral);

        // start interact : we need send token! call transferfrom()
        (bool successs) = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!successs) {
            revert DSCEngine__TransferFailed();
        }
    }

    /**
     * @param tokenCollateralAddress The address of the token collateral to redeem
     * @param amountCollateral The amount of collateral to redeem
     * @param amountDscToBurn The amount of dsc to burn
     * @notice This function burns DSC and redeem collateral in one transaction.
     */
    function redeemCollateralForDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToBurn)
        external
    {
        burnDsc(amountDscToBurn); //The order of burn and redeem must be notice!
        redeemCollateral(tokenCollateralAddress, amountCollateral);
    }

    //in order to redeem our collateral:
    // 1. health factor must be over 1 after collateral pulled
    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        nonReentrant
    {
        _redeemCollateral(msg.sender, msg.sender, tokenCollateralAddress, amountCollateral);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /*
     * @param amountDscToMint:The amount of decetralized stablecoin to mint
     * @notice they must have more than collateral value than the minimum threshold
     */
    // $200 ETH -> $50 DSC
    function mintDsc(uint256 amountDscToMint) public moreThanZero(amountDscToMint) nonReentrant {
        //effect: s_tokenamout[address] += _amount
        s_DscMinted[msg.sender] += amountDscToMint;
        //check address has collateral balance >= mintAmount. check priceFeeds,values. if mint make healthfactor broken, revert
        _revertIfHealthFactorIsBroken(msg.sender);
        //interact: send{value:100, address(this)}(), s_scAmount += _amount
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    function burnDsc(uint256 amountDscToBurn) public moreThanZero(amountDscToBurn) {
        _burnDsc(msg.sender, msg.sender, amountDscToBurn);
        _revertIfHealthFactorIsBroken(msg.sender); // maybe dont need this.
    }

    /**
     * @param user The user who has bad health factor
     */
    function liquidate(address collateral, address user, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
        nonReentrant
    {
        //1. check user's health factor
        uint256 startingHealthFactor = _healthFactor(user);
        if (startingHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
        } //if ok, cant liquidate the ok user
        // 2. burn their DSC and take their collateral
        // get their collateral value latest.
        uint256 currentValueOfdebtToCover = getTokenAmountFromUsd(collateral, debtToCover);
        // 3.give liquidator 10% bonus
        uint256 bonusCollateral = (currentValueOfdebtToCover * LIQUIDATION_BOUNS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = currentValueOfdebtToCover + bonusCollateral;

        //redeem collateral and burn DSC
        _redeemCollateral(user, msg.sender, collateral, totalCollateralToRedeem);
        _burnDsc(msg.sender, user, debtToCover);

        uint256 endingHealthFactor = _healthFactor(user);
        if (endingHealthFactor <= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorNotImprove();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /////////////////////////////////
    // internal & private function //
    /////////////////////////////////
    function _calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd)
        private
        pure
        returns (uint256)
    {
        if (totalDscMinted == 0) {
            return type(uint256).max;
        }
        uint256 totalCollateralAdjustedValueForThreshold =
            (collateralValueInUsd * LIQUIDATION_THRESHOLD / LIQUIDATION_PRECISION);
        // $100 ETH * 50/100 = 50$
        // $50 / $50DSC = <1
        return ((totalCollateralAdjustedValueForThreshold * PRECISION) / totalDscMinted); //notice the precision of totalDscMinted and it comes from the amount in mint function
            // return (totalCollateralValueInUSD / totalDscMinted);
    }

    /**
     * @dev Low-level internal function, do not call unless the function calling it is checking for health factors being broken
     * @param onBehalfOf The debt owner address of who's DSC needs to be burned.债务人
     * @param dscFrom The address who pay DSC for debt.还款人
     */
    function _burnDsc(address dscFrom, address onBehalfOf, uint256 amountDscToBurn) internal {
        s_DscMinted[onBehalfOf] -= amountDscToBurn;
        bool success = i_dsc.transferFrom(dscFrom, address(this), amountDscToBurn);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountDscToBurn);
    }

    function _redeemCollateral(address from, address to, address tokenCollateralAddress, uint256 amountCollateral)
        internal
    {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral); //IERC20 ?
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 totalCollateralValueInUSD)
    {
        totalDscMinted = s_DscMinted[user];
        totalCollateralValueInUSD = getAccountCollateralValue(user);
    }

    /**
     * returns how close to liquidationa a user is.
     * If a user goes below threshold, then they can get liquidated
     * big bug?
     * user is address(0)
     */
    function _healthFactor(address user) private view returns (uint256) {
        // total DSC minted
        // total collateral value
        (uint256 totalDscMinted, uint256 totalCollateralValueInUSD) = _getAccountInformation(user);
        return _calculateHealthFactor(totalDscMinted, totalCollateralValueInUSD); //notice the precision of totalDscMinted and it comes from the amount in mint function
            // return (totalCollateralValueInUSD / totalDscMinted);
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        //check healthfactor(do they have enough collateral)
        //revert if they dont have.
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorBroken(userHealthFactor);
        }
    }

    /////////////////////////////////
    // public & external view function        //
    /////////////////////////////////
    function calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd)
        external
        pure
        returns (uint256)
    {
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }

    function getAccountCollateralValue(address user) public view returns (uint256 accountCollateralValue) {
        // loop through each collateral token, get the amount they have deposited, and map it to the price, to get the USD value
        for (uint256 i = 0; i < s_collateralToken.length; i++) {
            address token = s_collateralToken[i];
            uint256 amount = s_collateralDeposited[user][token];
            accountCollateralValue += getUsdValue(token, amount);
        }
        return accountCollateralValue;
    }

    // ETH -> USD
    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_tokenToPriceFeed[token]);
        (, int256 price,,,) = priceFeed.checkStaleLatestRoundData();
        //ensure the precision of the number: eg. 1ETH = $1000
        // the return value from chainlink will be 1000 * 1e8
        return ((uint256(price) * ADD_FEED_PRECISION) * amount) / PRECISION;
    }

    // USD -> ETH
    function getTokenAmountFromUsd(address token, uint256 usdAmount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_tokenToPriceFeed[token]);
        (, int256 price,,,) = priceFeed.checkStaleLatestRoundData();

        return (usdAmount * PRECISION) / (uint256(price) * ADD_FEED_PRECISION);
        // $100 * 1e18 / $2000e8(price of ETH) * 1e10 = 0.05个ETH = 0.05e18 Wei
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }

    function getAccountInformation(address user)
        public
        view
        returns (uint256 totalDscMinted, uint256 totalCollateralValueInUSD)
    {
        (totalDscMinted, totalCollateralValueInUSD) = _getAccountInformation(user);
    }

    function getUserCollateralAmount(address user, address token) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }

    function getUserDscMintedAmount(address user) external view returns (uint256) {
        return s_DscMinted[user];
    }

    function getTokenPriceFeed(address token) external view returns (address) {
        return s_tokenToPriceFeed[token];
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralToken;
    }

    function getUserHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }

    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getLiquidationPrecision() external pure returns (uint256) {
        return LIQUIDATION_PRECISION;
    }

    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATION_BOUNS;
    }

    function getAdditionalFeedPrecision() external pure returns (uint256) {
        return ADD_FEED_PRECISION;
    }

    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    function getMinimumHealthFactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    function getDsc() external view returns (address) {
        return address(i_dsc);
    }

    function getCollateralTokenPriceFeed(address token) external view returns (address) {
        return s_tokenToPriceFeed[token];
    }
}
