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

    /// @notice Thrown when a non-owner calls an owner-only function.
    error NotOwner();

    /// @notice Thrown when an operation is attempted after the vault has been swept.
    error VaultSwept();

    /// @notice Thrown when the zero address is supplied where it is not allowed.
    error ZeroAddress();

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice ETH balance of each depositor.
    mapping(address => uint256) public balanceOf;

    /// @notice Sum of all currently deposited ETH (mirrors address(this).balance).
    uint256 public totalDeposits;

    /// @notice Owner address with rights to invoke the emergency hatch.
    address public owner;

    /// @notice One-way flag set when the emergency sweep has been executed.
    /// @dev When true, deposits and withdrawals are permanently disabled to
    ///      preserve ledger consistency (sum(balanceOf) would otherwise diverge
    ///      from totalDeposits / address(this).balance).
    bool public swept;

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

    /// @notice Emitted when ownership is transferred.
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /*//////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier notSwept() {
        if (swept) revert VaultSwept();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Deploys the vault and assigns ownership to the deployer.
    /// @dev Ownership should be moved to a multisig/timelock for production use.
    constructor() {
        owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                              EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Transfer ownership to a new account.
    /// @param newOwner The new owner address.
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        address previous = owner;
        owner = newOwner;
        emit OwnershipTransferred(previous, newOwner);
    }

    /// @notice Deposit ETH into the vault.
    /// @dev msg.value must be > 0.
    function deposit() external payable notSwept {
        if (msg.value == 0) revert ZeroDeposit();

        // Effects before interactions (CEI).
        balanceOf[msg.sender] += msg.value;
        totalDeposits += msg.value;

        emit Deposited(msg.sender, msg.value);
    }

    /// @notice Withdraw `amount` wei from the vault.
    /// @param amount Wei to withdraw.
    function withdraw(uint256 amount) external notSwept {
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
    /// @dev Owner-gated emergency hatch. Permanently disables deposits and
    ///      withdrawals via the one-way `swept` flag to prevent accounting
    ///      drift between balanceOf and totalDeposits.
    /// @param to Recipient of swept funds.
    function emergencySweep(address to) external onlyOwner notSwept {
        if (to == address(0)) revert ZeroAddress();

        // Effects: mark swept and zero global accounting BEFORE the external call.
        swept = true;
        totalDeposits = 0;

        uint256 amount = address(this).balance;

        // Interaction last.
        (bool ok,) = to.call{value: amount}("");
        if (!ok) revert TransferFailed();

        emit EmergencySwept(to, amount);
    }
}
