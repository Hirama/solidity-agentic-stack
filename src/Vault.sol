// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// THIS IS A PLACEHOLDER. Delete and replace with your protocol.

/// @title Vault
/// @notice Minimal ETH vault — deposit and withdraw ETH with per-user balance tracking.
/// @dev Demonstrates checks-effects-interactions and custom errors. Not production-ready.
contract Vault {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when a withdraw amount exceeds the caller's balance.
    error InsufficientBalance(uint256 requested, uint256 available);

    /// @notice Thrown when a zero-value deposit is attempted.
    error ZeroDeposit();

    /// @notice Thrown when ETH transfer to the caller fails.
    error TransferFailed();

    /// @notice Thrown when the vault has been permanently paused via emergency sweep.
    error VaultPaused();

    /// @notice Thrown when a non-owner attempts to call an owner-gated function.
    error NotOwner();

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice ETH balance of each depositor.
    mapping(address => uint256) public balanceOf;

    /// @notice Sum of all currently deposited ETH (tracked independently of address(this).balance).
    /// @dev address(this).balance may exceed totalDeposits if ETH is force-fed via selfdestruct
    ///      or coinbase rewards. Accounting must rely on this value, not on the raw balance.
    uint256 public totalDeposits;

    /// @notice Whether the vault has been permanently paused (e.g., after an emergency sweep).
    /// @dev Once true, deposits and withdrawals are disabled forever to prevent stale balance abuse.
    bool public paused;

    /// @notice The owner authorized to invoke owner-gated functions (e.g., emergencySweep).
    address public immutable owner;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted on a successful deposit.
    /// @param depositor Address that deposited.
    /// @param amount    Wei deposited.
    event Deposited(address indexed depositor, uint256 amount);

    /// @notice Emitted on a successful withdrawal.
    /// @param withdrawer Address that withdrew.
    /// @param amount     Wei withdrawn.
    event Withdrawn(address indexed withdrawer, uint256 amount);

    /// @notice Emitted on emergency sweep.
    /// @param to     Recipient of swept funds.
    /// @param amount Wei swept.
    event EmergencySwept(address indexed to, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Restricts a function to the vault owner.
    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes the vault and assigns ownership to the deployer.
    constructor() {
        owner = msg.sender;
    }

    /*//////////////////////////////////////////////////////////////
                              EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposit ETH into the vault.
    /// @dev msg.value must be > 0.
    function deposit() external payable {
        if (paused) revert VaultPaused();
        if (msg.value == 0) revert ZeroDeposit();

        // Effects before interactions (CEI).
        balanceOf[msg.sender] += msg.value;
        totalDeposits += msg.value;

        emit Deposited(msg.sender, msg.value);
    }

    /// @notice Withdraw `amount` wei from the vault.
    /// @param amount Wei to withdraw.
    function withdraw(uint256 amount) external {
        if (paused) revert VaultPaused();
        uint256 available = balanceOf[msg.sender];
        if (amount > available) revert InsufficientBalance(amount, available);

        // Effects before interactions (CEI).
        balanceOf[msg.sender] = available - amount;
        totalDeposits -= amount;

        // Interaction last.
        (bool ok,) = msg.sender.call{value: amount}("");
        if (!ok) revert TransferFailed();

        emit Withdrawn(msg.sender, amount);
    }

    /// @notice Emergency drain — sweeps accounted vault funds to `to`.
    /// @dev Owner-gated emergency hatch. Permanently pauses the vault so that
    ///      stale per-user balances cannot be redeemed against future deposits.
    ///      Only `totalDeposits` is swept; any ETH force-fed via selfdestruct or
    ///      coinbase rewards is intentionally left behind to preserve the
    ///      accounting invariant and avoid mixing donated ETH into the sweep.
    /// @param to Recipient of swept funds.
    function emergencySweep(address to) external onlyOwner {
        if (paused) revert VaultPaused();

        // Sweep only accounted deposits, not address(this).balance, which may be
        // inflated by force-fed ETH (selfdestruct / coinbase).
        uint256 amount = totalDeposits;

        // Effects before interactions (CEI): zero accounting and permanently pause
        // the vault so deposit/withdraw cannot resume against stale balanceOf entries.
        totalDeposits = 0;
        paused = true;

        (bool ok,) = to.call{value: amount}("");
        if (!ok) revert TransferFailed();

        emit EmergencySwept(to, amount);
    }
}
