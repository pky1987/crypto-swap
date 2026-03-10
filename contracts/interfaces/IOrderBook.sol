// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IOrderBook
 * @notice Interface for the order book escrow and settlement contracts.
 *         This is for Phase 4 — included here for completeness.
 *
 * HYBRID ORDER BOOK MODEL:
 * - Users deposit tokens into the escrow contract
 * - Orders are matched off-chain by the matching engine
 * - Matched trades are settled on-chain for trustlessness
 * - Users can withdraw unmatched funds at any time
 */
interface IOrderBook {
    enum OrderType { LIMIT, MARKET }
    enum OrderSide { BUY, SELL }

    struct Order {
        uint256 id;
        address trader;
        OrderSide side;
        uint256 price;    // Price in quote token (scaled by 10^18)
        uint256 amount;   // Amount of base token
        uint256 filled;   // Amount already filled
        uint256 timestamp;
        bool active;
    }

    event OrderPlaced(uint256 indexed orderId, address indexed trader, OrderSide side, uint256 price, uint256 amount);
    event OrderCancelled(uint256 indexed orderId);
    event TradeExecuted(uint256 indexed buyOrderId, uint256 indexed sellOrderId, uint256 price, uint256 amount);
    event Deposit(address indexed user, address indexed token, uint256 amount);
    event Withdrawal(address indexed user, address indexed token, uint256 amount);

    /// @notice Deposit tokens into the escrow
    function deposit(address token, uint256 amount) external;

    /// @notice Withdraw tokens from the escrow
    function withdraw(address token, uint256 amount) external;

    /// @notice Get user's escrowed balance
    function balanceOf(address user, address token) external view returns (uint256);

    /// @notice Execute a batch of matched trades (called by the matching engine)
    function executeTrades(
        uint256[] calldata buyOrderIds,
        uint256[] calldata sellOrderIds,
        uint256[] calldata amounts,
        uint256[] calldata prices
    ) external;
}
