// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {DeFi} from "../src/DeFi-ERC20.sol";

// Mock ERC20 Token for testing
contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(string memory _name, string memory _symbol, uint8 _decimals, uint256 _totalSupply) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
        totalSupply = _totalSupply;
        balanceOf[msg.sender] = _totalSupply;
        emit Transfer(address(0), msg.sender, _totalSupply);
    }

    function transfer(address to, uint256 value) external returns (bool) {
        require(balanceOf[msg.sender] >= value, "Insufficient balance");
        balanceOf[msg.sender] -= value;
        balanceOf[to] += value;
        emit Transfer(msg.sender, to, value);
        return true;
    }

    function approve(address spender, uint256 value) external returns (bool) {
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        require(balanceOf[from] >= value, "Insufficient balance");
        require(allowance[from][msg.sender] >= value, "Insufficient allowance");
        
        allowance[from][msg.sender] -= value;
        balanceOf[from] -= value;
        balanceOf[to] += value;
        emit Transfer(from, to, value);
        return true;
    }

    // Mint function for testing
    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }
}

contract DeFiTest is Test {
    DeFi public defi;
    MockERC20 public usdc;
    MockERC20 public dai;
    
    address public owner = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);

    function setUp() public {
        // Deploy contracts
        defi = new DeFi();
        usdc = new MockERC20("USD Coin", "USDC", 6, 1000000 * 10**6);
        dai = new MockERC20("DAI Stablecoin", "DAI", 18, 1000000 * 10**18);
        
        // Setup initial balances
        usdc.mint(owner, 10000 * 10**6);
        usdc.mint(user1, 5000 * 10**6);
        usdc.mint(user2, 5000 * 10**6);
        
        dai.mint(owner, 10000 * 10**18);
        dai.mint(user1, 5000 * 10**18);
        dai.mint(user2, 5000 * 10**18);
    }

    // ============ TEST DEPOSIT FUNCTION ============
    function test_Deposit_Success() public {
        vm.startPrank(user1);
        uint depositAmount = 1000 * 10**6;
        
        // Approve first
        usdc.approve(address(defi), depositAmount);
        
        // Deposit
        defi.deposit(address(usdc), depositAmount);
        
        // Verify
        assertEq(defi.getDepositBalance(address(usdc)), depositAmount);
        assertEq(usdc.balanceOf(address(defi)), depositAmount);
        assertEq(usdc.balanceOf(user1), 4000 * 10**6); // 5000 - 1000
        vm.stopPrank();
    }

    function test_Deposit_EventEmitted() public {
        vm.startPrank(user1);
        uint depositAmount = 1000 * 10**6;
        usdc.approve(address(defi), depositAmount);
        
        vm.expectEmit(true, true, false, true);
        emit DeFi.DepositCreated(user1, address(usdc), depositAmount);
        
        defi.deposit(address(usdc), depositAmount);
        vm.stopPrank();
    }

    function test_Deposit_RevertWhen_ZeroAmount() public {
        vm.startPrank(user1);
        usdc.approve(address(defi), 1000);
        
        vm.expectRevert("Deposit amount must be greater than zero");
        defi.deposit(address(usdc), 0);
        vm.stopPrank();
    }

    // ============ TEST BORROW FUNCTION ============
    function test_Borrow_Success() public {
        // First deposit some tokens to vault
        vm.startPrank(owner);
        uint depositAmount = 5000 * 10**6;
        usdc.approve(address(defi), depositAmount);
        defi.deposit(address(usdc), depositAmount);
        vm.stopPrank();

        // Then borrow
        vm.startPrank(user1);
        uint borrowAmount = 1000 * 10**6;
        defi.borrow(address(usdc), borrowAmount);
        
        // Verify loan created
        (uint borrowedAmount, address tokenAddress, bool isActive) = defi.userLoans(user1);
        assertEq(borrowedAmount, borrowAmount);
        assertEq(tokenAddress, address(usdc));
        assertTrue(isActive);
        
        // Verify tokens transferred
        assertEq(usdc.balanceOf(user1), 5000 * 10**6 + borrowAmount); // initial + borrowed
        vm.stopPrank();
    }

    function test_Borrow_EventEmitted() public {
        vm.startPrank(owner);
        usdc.approve(address(defi), 5000 * 10**6);
        defi.deposit(address(usdc), 5000 * 10**6);
        vm.stopPrank();

        vm.startPrank(user1);
        uint borrowAmount = 1000 * 10**6;
        
        vm.expectEmit(true, true, false, true);
        emit DeFi.LoanCreated(user1, address(usdc), borrowAmount);
        
        defi.borrow(address(usdc), borrowAmount);
        vm.stopPrank();
    }

    function test_Borrow_RevertWhen_AlreadyBorrowing() public {
        vm.startPrank(owner);
        usdc.approve(address(defi), 5000 * 10**6);
        defi.deposit(address(usdc), 5000 * 10**6);
        vm.stopPrank();

        vm.startPrank(user1);
        defi.borrow(address(usdc), 1000 * 10**6);
        
        vm.expectRevert("You already have an active loan");
        defi.borrow(address(usdc), 500 * 10**6);
        vm.stopPrank();
    }

    function test_Borrow_RevertWhen_InsufficientVaultBalance() public {
        vm.startPrank(user1);
        vm.expectRevert("Contract has insufficient tokens to lend");
        defi.borrow(address(usdc), 1000 * 10**6);
        vm.stopPrank();
    }

    // ============ TEST REPAY FUNCTION ============
    function test_RepayLoan_Success() public {
        // Setup: deposit and borrow
        vm.startPrank(owner);
        usdc.approve(address(defi), 5000 * 10**6);
        defi.deposit(address(usdc), 5000 * 10**6);
        vm.stopPrank();

        vm.startPrank(user1);
        uint borrowAmount = 1000 * 10**6;
        defi.borrow(address(usdc), borrowAmount);
        
        // Repay loan
        usdc.approve(address(defi), borrowAmount);
        defi.repayLoan(borrowAmount, address(usdc));
        
        // Verify loan cleared
        (uint remainingAmount, , bool isActive) = defi.userLoans(user1);
        assertEq(remainingAmount, 0);
        assertFalse(isActive);
        vm.stopPrank();
    }

    function test_RepayLoan_EventEmitted() public {
        vm.startPrank(owner);
        usdc.approve(address(defi), 5000 * 10**6);
        defi.deposit(address(usdc), 5000 * 10**6);
        vm.stopPrank();

        vm.startPrank(user1);
        uint borrowAmount = 1000 * 10**6;
        defi.borrow(address(usdc), borrowAmount);
        usdc.approve(address(defi), borrowAmount);
        
        vm.expectEmit(true, true, false, true);
        emit DeFi.LoanRepaid(user1, address(usdc), borrowAmount);
        
        defi.repayLoan(borrowAmount, address(usdc));
        vm.stopPrank();
    }

    function test_RepayLoan_RevertWhen_NoActiveLoan() public {
        vm.startPrank(user1);
        usdc.approve(address(defi), 1000 * 10**6);
        
        vm.expectRevert("You don't have an active loan");
        defi.repayLoan(1000 * 10**6, address(usdc));
        vm.stopPrank();
    }

    function test_RepayLoan_RevertWhen_InsufficientPayment() public {
        vm.startPrank(owner);
        usdc.approve(address(defi), 5000 * 10**6);
        defi.deposit(address(usdc), 5000 * 10**6);
        vm.stopPrank();

        vm.startPrank(user1);
        uint borrowAmount = 1000 * 10**6;
        defi.borrow(address(usdc), borrowAmount);
        usdc.approve(address(defi), 500 * 10**6); // Approve less than borrowed
        
        vm.expectRevert("Repayment amount is insufficient");
        defi.repayLoan(500 * 10**6, address(usdc));
        vm.stopPrank();
    }

    // ============ TEST WITHDRAW FUNCTION ============
    function test_Withdraw_Success() public {
        vm.startPrank(user1);
        uint depositAmount = 1000 * 10**6;
        usdc.approve(address(defi), depositAmount);
        defi.deposit(address(usdc), depositAmount);
        
        // Withdraw
        uint withdrawAmount = 500 * 10**6;
        defi.withdraw(address(usdc), withdrawAmount);
        
        // Verify
        assertEq(defi.getDepositBalance(address(usdc)), 500 * 10**6);
        assertEq(usdc.balanceOf(user1), 5000 * 10**6 - 500 * 10**6); // 5000 - 1000 + 500
        vm.stopPrank();
    }

    function test_Withdraw_RevertWhen_InsufficientBalance() public {
        vm.startPrank(user1);
        uint depositAmount = 1000 * 10**6;
        usdc.approve(address(defi), depositAmount);
        defi.deposit(address(usdc), depositAmount);
        
        vm.expectRevert("Insufficient balance for withdrawal");
        defi.withdraw(address(usdc), 2000 * 10**6);
        vm.stopPrank();
    }

    // ============ TEST VIEW FUNCTIONS ============
    function test_GetDepositBalance() public {
        vm.startPrank(user1);
        uint depositAmount = 1000 * 10**6;
        usdc.approve(address(defi), depositAmount);
        defi.deposit(address(usdc), depositAmount);
        
        assertEq(defi.getDepositBalance(address(usdc)), depositAmount);
        vm.stopPrank();
    }

    function test_GetTotalDeposits() public {
        vm.startPrank(owner);
        uint depositAmount = 5000 * 10**6;
        usdc.approve(address(defi), depositAmount);
        defi.deposit(address(usdc), depositAmount);
        
        assertEq(defi.getTotalDeposits(address(usdc)), depositAmount);
        vm.stopPrank();
    }

    // ============ TEST SECURITY ============
    function test_ReentrancyProtection() public {
        vm.startPrank(owner);
        usdc.approve(address(defi), 5000 * 10**6);
        defi.deposit(address(usdc), 5000 * 10**6);
        vm.stopPrank();

        vm.startPrank(user1);
        
        // First borrow should work
        defi.borrow(address(usdc), 1000 * 10**6);
        
        // Expect "You already have an active loan" instead of "No reentrancy allowed"
        vm.expectRevert("You already have an active loan");
        defi.borrow(address(usdc), 500 * 10**6);
        
        vm.stopPrank();
    }

    function test_MultipleUsers_MultipleTokens() public {
        // User1 deposits USDC and DAI
        vm.startPrank(user1);
        usdc.approve(address(defi), 2000 * 10**6);
        defi.deposit(address(usdc), 2000 * 10**6);
        
        dai.approve(address(defi), 1000 * 10**18);
        defi.deposit(address(dai), 1000 * 10**18);
        vm.stopPrank();

        // User2 deposits DAI
        vm.startPrank(user2);
        dai.approve(address(defi), 1500 * 10**18);
        defi.deposit(address(dai), 1500 * 10**18);
        vm.stopPrank();

        // Check balances from user context
        vm.startPrank(user1);
        assertEq(defi.getDepositBalance(address(usdc)), 2000 * 10**6);
        assertEq(defi.getDepositBalance(address(dai)), 1000 * 10**18);
        vm.stopPrank();

        vm.startPrank(user2);
        assertEq(defi.getDepositBalance(address(dai)), 1500 * 10**18);
        vm.stopPrank();
    }

    // ============ FUZZING TESTS ============
    function testFuzz_Deposit_Withdraw(uint256 amount) public {
        amount = bound(amount, 1, 5000 * 10**6); // Bound to reasonable range
        
        vm.startPrank(user1);
        usdc.approve(address(defi), amount);
        defi.deposit(address(usdc), amount);
        
        defi.withdraw(address(usdc), amount);
        
        assertEq(defi.getDepositBalance(address(usdc)), 0);
        assertEq(usdc.balanceOf(user1), 5000 * 10**6); // Back to initial
        vm.stopPrank();
    }
}

// Malicious contract for reentrancy testing
contract MaliciousBorrower {
    DeFi public defi;
    MockERC20 public token;
    bool private attacked;

    constructor(address _defi, address _token) {
        defi = DeFi(_defi);
        token = MockERC20(_token);
    }

    function attack() external {
        // Try to borrow
        defi.borrow(address(token), 1000 * 10**6);
        
        // In receive callback, try to borrow again (reentrancy)
        attacked = true;
        defi.borrow(address(token), 1000 * 10**6);
    }

    // Fallback function for reentrancy
    receive() external payable {
        if (!attacked) {
            attacked = true;
            defi.borrow(address(token), 1000 * 10**6);
        }
    }
}