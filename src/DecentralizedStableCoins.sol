// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/*
 * @title DecentralizedStableCoins
 * @author Jaunepr
 * @notice Relative Stability:Pegged to USD
 * Collateral: 外部抵押(ETH & BTC)
 * Stability Method: Algorithmic
 *
 */

contract DecentralizedStableCoins is ERC20Burnable, Ownable {
    error DecentralizedStableCoins__MustBeMoreThanZero();
    error DecentralizedStableCoins__BalanceNotEnoughBurned();
    error DecentralizedStableCoins__NotZeroAddress();

    constructor() ERC20("DecentralizedStableCoins", "DSC") Ownable(msg.sender) {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert DecentralizedStableCoins__MustBeMoreThanZero();
        }
        if (_amount > balance) {
            revert DecentralizedStableCoins__BalanceNotEnoughBurned();
        }
        super.burn(_amount);
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert DecentralizedStableCoins__NotZeroAddress();
        }
        if (_amount <= 0) {
            revert DecentralizedStableCoins__MustBeMoreThanZero();
        }
        _mint(_to, _amount);
        return true;
    }
}
