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

    /// @notice Thrown when a non-owner calls an owner-gated function.
    error NotOwner();

    /// @notice Thrown when a non-pending-owner calls acceptOwnership.
    error NotPendingOwner();

    /// @notice Thrown when a zero address is supplied where disallowed.
    error ZeroAddress();

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice ETH balance of each depositor.
    mapping(address => uint256) public balanceOf;

    /// @notice Sum of all currently deposited ETH (mirrors address(this).balance).
    uint256 public totalDeposits;

    /// @notice Owner authorized to invoke emergency operations.
    address public owner;

    /// @notice Pending owner in a two-step ownership handover.
    address public pendingOwner;

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

    /// @notice Emitted when a new pending owner is nominated.
    /// @param previousPendingOwner Previously nominated pending owner.
    /// @param newPendingOwner      Newly nominated pending owner.
    event OwnershipTransferStarted(address indexed previousPendingOwner, address indexed newPendingOwner);

    /// @notice Emitted when ownership is transferred.
    /// @param previousOwner Previous owner.
    /// @param newOwner      New owner.
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Restricts a function to the contract owner.
    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Sets the deployer as the initial owner.
    constructor() {
        owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                              EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposit ETH into the vault.
    /// @dev msg.value must be > 0.
    function deposit() external payable {
        if (msg.value == 0) revert ZeroDeposit();

        // Effects before interactions (CEI).
        balanceOf[msg.sender] += msg.value;
        totalDeposits += msg.value;

        emit Deposited(msg.sender, msg.value);
    }

    /// @notice Withdraw `amount` wei from the vault.
    /// @param amount Wei to withdraw.
    function withdraw(uint256 amount) external {
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
    /// @dev Owner-gated emergency hatch. Recipient must be non-zero.
    /// @param to Recipient of swept funds.
    function emergencySweep(address to) external onlyOwner {
        if (to == address(0)) revert ZeroAddress();

        uint256 amount = address(this).balance;
        totalDeposits = 0;

        (bool ok,) = to.call{value: amount}("");
        if (!ok) revert TransferFailed();

        emit EmergencySwept(to, amount);
    }

    /// @notice Begin a two-step ownership transfer by nominating a new pending owner.
    /// @dev Only the current owner may call. Pass address(0) to cancel a pending transfer.
    /// @param newOwner The address nominated to become the next owner.
    function transferOwnership(address newOwner) external onlyOwner {
        address previousPendingOwner = pendingOwner;
        pendingOwner = newOwner;
        emit OwnershipTransferStarted(previousPendingOwner, newOwner);
    }

    /// @notice Complete a two-step ownership transfer.
    /// @dev Only the pending owner may call.
    function acceptOwnership() external {
        address newOwner = msg.sender;
        if (newOwner != pendingOwner) revert NotPendingOwner();

        address previousOwner = owner;
        owner = newOwner;
        pendingOwner = address(0);
        emit OwnershipTransferred(previousOwner, newOwner);
    }

    /// @notice Renounce ownership, leaving the contract without an owner.
    /// @dev Only the current owner may call. Emergency operations will no longer be callable.
    function renounceOwnership() external onlyOwner {
        address previousOwner = owner;
        owner = address(0);
        pendingOwner = address(0);
        emit OwnershipTransferred(previousOwner, address(0));
    }
}
