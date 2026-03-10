// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MockERC20
 * @notice A simple ERC20 token for testing swaps and liquidity on the AMM.
 *         In production, you'd interact with real tokens. This contract is
 *         used for local development and testnet deployments.
 *
 * KEY CONCEPTS FOR LEARNING:
 * - ERC20 is the standard token interface on Ethereum
 * - `mint()` creates new tokens (only owner can call it)
 * - `decimals()` defines how many decimal places the token uses (like cents for dollars)
 * - We inherit from OpenZeppelin's audited ERC20 implementation for safety
 */
contract MockERC20 is ERC20, Ownable {
    uint8 private _decimals;

    /**
     * @param name_ Token name (e.g., "USD Coin")
     * @param symbol_ Token symbol (e.g., "USDC")
     * @param decimals_ Number of decimal places (usually 18, USDC uses 6)
     */
    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_
    ) ERC20(name_, symbol_) Ownable(msg.sender) {
        _decimals = decimals_;
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    /**
     * @notice Mint tokens to an address. Only the owner can call this.
     * @dev In a real token, minting is usually restricted or non-existent.
     *      We use this for testing — mint yourself tokens to swap.
     * @param to The address to receive the tokens
     * @param amount The amount to mint (in the token's smallest unit)
     *
     * EXAMPLE: To mint 1000 USDC (6 decimals):
     *   mint(yourAddress, 1000 * 10^6)  →  mint(yourAddress, 1000000000)
     */
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    /**
     * @notice Burn tokens from an address. Only the owner can call this.
     * @param from The address to burn tokens from
     * @param amount The amount to burn
     */
    function burn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
    }
}
