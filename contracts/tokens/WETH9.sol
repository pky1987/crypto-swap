// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title WETH9 — Wrapped Ether
 * @notice This wraps native ETH into an ERC20 token (WETH).
 *
 * WHY DO WE NEED THIS?
 * - ETH is the native currency of Ethereum, but it doesn't follow the ERC20 standard
 * - AMMs (like Uniswap) only work with ERC20 tokens
 * - WETH wraps ETH into an ERC20 so the AMM can treat it like any other token
 * - 1 WETH = 1 ETH always (you can wrap/unwrap freely)
 *
 * HOW IT WORKS:
 * 1. Send ETH to this contract → you receive WETH (ERC20)
 * 2. Call withdraw() → you get your ETH back, WETH is burned
 *
 * This is the canonical WETH9 contract used on Ethereum mainnet,
 * adapted to Solidity 0.8.x with safety checks.
 */
contract WETH9 {
    string public name = "Wrapped Ether";
    string public symbol = "WETH";
    uint8 public decimals = 18;

    event Approval(address indexed src, address indexed guy, uint wad);
    event Transfer(address indexed src, address indexed dst, uint wad);
    event Deposit(address indexed dst, uint wad);
    event Withdrawal(address indexed src, uint wad);

    mapping(address => uint) public balanceOf;
    mapping(address => mapping(address => uint)) public allowance;

    /**
     * @notice Deposit ETH and receive WETH.
     * Simply send ETH to this contract, and you'll get WETH tokens.
     *
     * EXAMPLE: If you send 1 ETH, you get 1 WETH.
     */
    receive() external payable {
        deposit();
    }

    function deposit() public payable {
        balanceOf[msg.sender] += msg.value;
        emit Deposit(msg.sender, msg.value);
    }

    /**
     * @notice Withdraw ETH by burning WETH.
     * @param wad Amount of WETH to burn (you get the same amount of ETH back)
     *
     * EXAMPLE: withdraw(1 ether) → burns 1 WETH, sends you 1 ETH
     */
    function withdraw(uint wad) public {
        require(balanceOf[msg.sender] >= wad, "WETH: insufficient balance");
        balanceOf[msg.sender] -= wad;
        payable(msg.sender).transfer(wad);
        emit Withdrawal(msg.sender, wad);
    }

    function totalSupply() public view returns (uint) {
        return address(this).balance;
    }

    function approve(address guy, uint wad) public returns (bool) {
        allowance[msg.sender][guy] = wad;
        emit Approval(msg.sender, guy, wad);
        return true;
    }

    function transfer(address dst, uint wad) public returns (bool) {
        return transferFrom(msg.sender, dst, wad);
    }

    function transferFrom(
        address src,
        address dst,
        uint wad
    ) public returns (bool) {
        require(balanceOf[src] >= wad, "WETH: insufficient balance");

        if (src != msg.sender && allowance[src][msg.sender] != type(uint).max) {
            require(allowance[src][msg.sender] >= wad, "WETH: insufficient allowance");
            allowance[src][msg.sender] -= wad;
        }

        balanceOf[src] -= wad;
        balanceOf[dst] += wad;

        emit Transfer(src, dst, wad);
        return true;
    }
}
