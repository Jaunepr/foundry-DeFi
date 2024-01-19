// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "../test/mocks/ERC20Mock.sol";

contract HelperConfig is Script {
    struct NetWorkConfig {
        address wethUsdPriceFeed;
        address wbtcUsdPriceFeed;
        address weth;
        address wbtc;
        uint256 deployerKey;
    }

    NetWorkConfig public activeNetWorkConfig;

    uint8 private constant DECIMALS = 8;
    int256 private constant ETH_USD_PRICE = 2000e8;
    int256 private constant BTC_USD_PRICE = 4000e8;
    uint256 private constant DEFAULT_ANVIL_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    constructor() {
        if (block.chainid == 11155111) {
            activeNetWorkConfig = getSepoliaEthConfig();
        } else {
            activeNetWorkConfig = getOrCreateAnvilConfig();
        }
    }

    function getSepoliaEthConfig() public view returns (NetWorkConfig memory sepoliaEthConfig) {
        sepoliaEthConfig = NetWorkConfig({
            wethUsdPriceFeed: 0x694AA1769357215dE4daC081bf1f309adC325306,
            wbtcUsdPriceFeed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
            weth: 0xdd13E55209Fd76AfE204dBda4007C227904f0a81,
            wbtc: 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063,
            deployerKey: vm.envUint("PRIVATE_KEY")
        });
        // return sepoliaEthConfig;
    }

    function getOrCreateAnvilConfig() public returns (NetWorkConfig memory anvilConfig) {
        if (activeNetWorkConfig.wethUsdPriceFeed != address(0)) {
            return activeNetWorkConfig;
        }
        vm.startBroadcast();
        MockV3Aggregator ethUsdPriceFeed = new MockV3Aggregator(DECIMALS, ETH_USD_PRICE);
        ERC20Mock weth = new ERC20Mock("WETH", "WETH", msg.sender, 2000e8);

        MockV3Aggregator btcUsdPriceFeed = new MockV3Aggregator(DECIMALS, BTC_USD_PRICE);
        ERC20Mock wbtc = new ERC20Mock("WBTC", "WBTC", msg.sender, 2000e8);
        vm.stopBroadcast();

        anvilConfig = NetWorkConfig({
            wethUsdPriceFeed: address(ethUsdPriceFeed),
            wbtcUsdPriceFeed: address(btcUsdPriceFeed),
            weth: address(weth),
            wbtc: address(wbtc),
            deployerKey: DEFAULT_ANVIL_KEY
        });
        // return anvilConfig;
    }
}
