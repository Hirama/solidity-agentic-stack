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

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice ETH balance of each depositor.
    mapping(address => uint256) public balanceOf;

    /// @notice Sum of all currently deposited ETH (mirrors address(this).balance).
    uint256 public totalDeposits;

    /// @notice Whether the vault has been permanently paused (e.g., after an emergency sweep).
    /// @dev Once true, deposits and withdrawals are disabled forever to prevent stale balance abuse.
    bool public paused;

    /// @dev List of addresses that have ever deposited, used to zero per-user balances on emergency sweep.
    address[] private _depositors;

    /// @dev Tracks whether an address is already present in `_depositors` to avoid duplicates.
    mapping(address => bool) private _isDepositor;

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
                              EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposit ETH into the vault.
    /// @dev msg.value must be > 0.
    function deposit() external payable {
        if (paused) revert VaultPaused();
        if (msg.value == 0) revert ZeroDeposit();

        // Effects before interactions (CEI).
        if (!_isDepositor[msg.sender]) {
            _isDepositor[msg.sender] = true;
            _depositors.push(msg.sender);
        }
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

    /// @notice Emergency drain — sweeps all vault funds to `to`.
    /// @dev Owner-gated emergency hatch. Permanently pauses the vault and zeros
    ///      every per-user balance so no stale accounting remains after the sweep.
    /// @param to Recipient of swept funds.
    function emergencySweep(address to) external {
        if (paused) revert VaultPaused();

        uint256 amount = address(this).balance;

        // Effects before interactions (CEI): zero all per-user accounting,
        // zero global accounting, and permanently pause the vault so that
        // deposit/withdraw cannot resume against stale balanceOf entries.
        uint256 len = _depositors.length;
        for (uint256 i = 0; i < len; ++i) {
            balanceOf[_depositors[i]] = 0;
        }
        totalDeposits = 0;
        paused = true;

        (bool ok,) = to.call{value: amount}("");
        if (!ok) revert TransferFailed();

        emit EmergencySwept(to, amount);
    }
}
