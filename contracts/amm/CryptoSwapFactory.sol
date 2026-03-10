// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./CryptoSwapPool.sol";
import "../interfaces/ICryptoSwapFactory.sol";

/**
 * @title CryptoSwapFactory
 * @author Prakash Yadav
 * @notice Creates and manages trading pools for token pairs.
 *
 * ═══════════════════════════════════════════════════════
 * 📚 LEARNING: HOW POOL CREATION WORKS
 * ═══════════════════════════════════════════════════════
 *
 * 1. A user calls createPool(tokenA, tokenB, fee)
 * 2. The factory checks no pool exists for this pair+fee combo
 * 3. It sorts the tokens (token0 < token1 by address) for consistency
 * 4. It deploys a new CryptoSwapPool contract
 * 5. It stores the pool address in a mapping for lookup
 *
 * WHY SORT TOKENS?
 * - ETH/USDC and USDC/ETH are the SAME pair
 * - By always putting the smaller address as token0, we avoid duplicates
 *
 * FEE TIERS:
 * - 500   = 0.05% (for stablecoin pairs like USDC/USDT)
 * - 3000  = 0.30% (for most pairs like ETH/USDC)
 * - 10000 = 1.00% (for exotic/volatile pairs)
 * ═══════════════════════════════════════════════════════
 */
contract CryptoSwapFactory is ICryptoSwapFactory {
    /// @notice Protocol fee collector address
    address public override feeCollector;

    /// @notice Owner of the factory (can update feeCollector)
    address public owner;

    /// @notice Mapping of fee amounts to tick spacing
    /// @dev Tick spacing determines the granularity of price ranges for LPs
    mapping(uint24 => int24) public feeAmountTickSpacing;

    /// @notice Pool lookup: token0 => token1 => fee => pool address
    mapping(address => mapping(address => mapping(uint24 => address))) public override getPool;

    /// @notice Array of all pools ever created
    address[] public override allPools;

    /// @notice Allowed fee tiers
    mapping(uint24 => bool) public feeEnabled;

    // ═══════════════════════════════════════
    //  Events
    // ═══════════════════════════════════════

    event OwnerChanged(address indexed oldOwner, address indexed newOwner);
    event FeeCollectorChanged(address indexed oldCollector, address indexed newCollector);
    event FeeAmountEnabled(uint24 indexed fee, int24 indexed tickSpacing);

    // ═══════════════════════════════════════
    //  Constructor
    // ═══════════════════════════════════════

    constructor() {
        owner = msg.sender;
        feeCollector = msg.sender;

        // Initialize default fee tiers
        // Fee is in hundredths of a basis point (1/100 of 0.01%)
        // So 500 = 0.05%, 3000 = 0.30%, 10000 = 1.00%
        _enableFeeAmount(500, 10);     // 0.05% fee, 10 tick spacing
        _enableFeeAmount(3000, 60);    // 0.30% fee, 60 tick spacing
        _enableFeeAmount(10000, 200);  // 1.00% fee, 200 tick spacing
    }

    // ═══════════════════════════════════════
    //  Core Functions
    // ═══════════════════════════════════════

    /**
     * @notice Creates a new pool for the given token pair and fee.
     * @param tokenA One of the tokens in the pair
     * @param tokenB The other token
     * @param fee The fee tier (500, 3000, or 10000)
     * @return pool The address of the newly created pool
     *
     * 📚 STEP BY STEP:
     * 1. Validate inputs (tokens different, fee valid)
     * 2. Sort tokens (smaller address = token0)
     * 3. Check pool doesn't already exist
     * 4. Deploy new pool contract
     * 5. Store in mapping (both directions for easy lookup)
     * 6. Emit event
     */
    function createPool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) external override returns (address pool) {
        require(tokenA != tokenB, "IDENTICAL_ADDRESSES");
        require(tokenA != address(0) && tokenB != address(0), "ZERO_ADDRESS");
        require(feeEnabled[fee], "FEE_NOT_ENABLED");

        // Sort tokens — convention: token0 has the smaller address
        (address token0, address token1) = tokenA < tokenB
            ? (tokenA, tokenB)
            : (tokenB, tokenA);

        // Check pool doesn't already exist
        require(getPool[token0][token1][fee] == address(0), "POOL_EXISTS");

        // Get tick spacing for this fee tier
        int24 tickSpacing = feeAmountTickSpacing[fee];

        // Deploy new pool contract using CREATE2 for deterministic addresses
        pool = address(
            new CryptoSwapPool{
                salt: keccak256(abi.encode(token0, token1, fee))
            }(address(this), token0, token1, fee, tickSpacing)
        );

        // Store pool in mapping (both directions for easy lookup)
        getPool[token0][token1][fee] = pool;
        getPool[token1][token0][fee] = pool;

        allPools.push(pool);

        emit PoolCreated(token0, token1, fee, pool);
    }

    // ═══════════════════════════════════════
    //  View Functions
    // ═══════════════════════════════════════

    /// @notice Returns total number of pools
    function allPoolsLength() external view override returns (uint256) {
        return allPools.length;
    }

    // ═══════════════════════════════════════
    //  Admin Functions
    // ═══════════════════════════════════════

    /// @notice Change the owner
    function setOwner(address _owner) external {
        require(msg.sender == owner, "NOT_OWNER");
        emit OwnerChanged(owner, _owner);
        owner = _owner;
    }

    /// @notice Change the fee collector
    function setFeeCollector(address _feeCollector) external {
        require(msg.sender == owner, "NOT_OWNER");
        emit FeeCollectorChanged(feeCollector, _feeCollector);
        feeCollector = _feeCollector;
    }

    /// @notice Enable a new fee tier
    function enableFeeAmount(uint24 fee, int24 tickSpacing) external {
        require(msg.sender == owner, "NOT_OWNER");
        _enableFeeAmount(fee, tickSpacing);
    }

    function _enableFeeAmount(uint24 fee, int24 tickSpacing) internal {
        require(fee < 1000000, "FEE_TOO_LARGE"); // Max 100%
        require(tickSpacing > 0 && tickSpacing < 16384, "INVALID_TICK_SPACING");
        require(!feeEnabled[fee], "FEE_ALREADY_ENABLED");

        feeAmountTickSpacing[fee] = tickSpacing;
        feeEnabled[fee] = true;

        emit FeeAmountEnabled(fee, tickSpacing);
    }
}
