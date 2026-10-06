// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Pegzeus} from "src/Pegzeus.sol";

/// @dev Complements the original suite with replay, identity, and uint256 boundary cases.
/// forge-config: default.fuzz.runs = 1000
contract PegzeusBoundaryTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant SPENDER = address(0x5EED);

    Pegzeus private token;

    function setUp() public {
        token = new Pegzeus();
    }

    function test_OneWeiDirectAndDelegatedRoundTrip() public {
        assertTrue(token.transfer(ALICE, 1));
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, 1));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, address(this), 1));
        assertEq(token.allowance(ALICE, SPENDER), 0);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_MaximumTransferCannotWrapBalance() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        token.transfer(ALICE, type(uint256).max);
        _assertInitialBalances();
    }

    function test_MaximumDelegatedAmountsPreserveFiniteAndInfiniteApprovalsOnFailure() public {
        // Both sides of the sentinel: MAX-1 is finite; MAX is an unlimited allowance.
        uint256[2] memory amounts = [type(uint256).max - 1, type(uint256).max];
        for (uint256 i; i < amounts.length; ++i) {
            uint256 amount = amounts[i];
            assertTrue(token.approve(SPENDER, amount));
            vm.expectRevert(
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, amount)
            );
            vm.prank(SPENDER);
            token.transferFrom(address(this), ALICE, amount);
            assertEq(token.allowance(address(this), SPENDER), amount);
            _assertInitialBalances();
        }
    }

    function test_MaximumFiniteAllowanceIsConsumed() public {
        assertTrue(token.approve(SPENDER, type(uint256).max - 1));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max - 2);
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ExhaustedAllowanceCannotBeReplayedAfterTokensReturn() public {
        assertTrue(token.approve(SPENDER, SUPPLY));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, SUPPLY));
        assertEq(token.allowance(address(this), SPENDER), 0);
        vm.prank(ALICE);
        assertTrue(token.transfer(address(this), SUPPLY));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.allowance(address(this), SPENDER), 0);
        _assertInitialBalances();
    }

    function test_AllowanceIsSpecificToBothOwnerAndSpender() public {
        assertTrue(token.transfer(ALICE, 10));
        assertTrue(token.transfer(BOB, 10));
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, 10));

        // A different caller cannot use SPENDER's approval for ALICE.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, BOB, 0, 1));
        vm.prank(BOB);
        token.transferFrom(ALICE, BOB, 1);
        // SPENDER cannot reuse ALICE's approval to spend BOB's equally funded balance.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(BOB, ALICE, 1);

        assertEq(token.allowance(ALICE, SPENDER), 10);
        assertEq(token.allowance(ALICE, BOB), 0);
        assertEq(token.allowance(BOB, SPENDER), 0);
        assertEq(token.balanceOf(ALICE), 10);
        assertEq(token.balanceOf(BOB), 10);
        assertEq(token.balanceOf(SPENDER), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - 20);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_SelfSpenderStillNeedsAllowance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(this), ALICE, 1);
        _assertInitialBalances();

        assertTrue(token.approve(address(this), 1));
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        assertEq(token.allowance(address(this), address(this)), 0);
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
    }

    function test_UnlimitedApprovalCanBeLoweredAndRevoked() public {
        assertTrue(token.approve(SPENDER, type(uint256).max));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max);

        assertTrue(token.approve(SPENDER, 1));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 1, 2));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 2);
        assertEq(token.allowance(address(this), SPENDER), 1);

        assertTrue(token.approve(SPENDER, type(uint256).max));
        assertTrue(token.approve(SPENDER, 0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroRecipientIsInvalidEvenForZeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);

        assertTrue(token.approve(SPENDER, type(uint256).max));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(address(this), address(0), 0);
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max);
        assertEq(token.balanceOf(address(0)), 0);
        _assertInitialBalances();
    }

    function test_ZeroSpenderIsInvalidForZeroAndMaximumApprovals() public {
        uint256[2] memory amounts = [uint256(0), type(uint256).max];
        for (uint256 i; i < amounts.length; ++i) {
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
            token.approve(address(0), amounts[i]);
            assertEq(token.allowance(address(this), address(0)), 0);
            _assertInitialBalances();
        }
    }

    function testFuzz_FiniteApprovalAcrossUint256Domain(uint256 approval, uint256 amount) public {
        approval = bound(approval, 0, type(uint256).max - 1);
        amount = bound(amount, 0, approval < SUPPLY ? approval : SUPPLY);
        assertTrue(token.approve(SPENDER, approval));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, amount));
        assertEq(token.allowance(address(this), SPENDER), approval - amount);
        assertEq(token.balanceOf(ALICE), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_SplittingAndReturningTransfersNeverLosesDust(uint256 amount, uint256 split) public {
        amount = bound(amount, 0, SUPPLY);
        split = bound(split, 0, amount);
        assertTrue(token.transfer(ALICE, split));
        assertEq(token.balanceOf(ALICE), split);
        assertTrue(token.transfer(ALICE, amount - split));
        assertEq(token.balanceOf(ALICE), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        vm.prank(ALICE);
        assertTrue(token.transfer(address(this), amount));
        _assertInitialBalances();
    }

    function testFuzz_TransferFromPaysArbitraryRecipientInFull(uint160 recipientSeed, uint256 amount) public {
        address recipient = address(uint160(bound(recipientSeed, 1, type(uint160).max)));
        // Keep the debit and credit accounts distinct without discarding fuzz runs.
        if (recipient == address(this)) recipient = ALICE;
        amount = bound(amount, 0, SUPPLY);
        assertTrue(token.approve(SPENDER, amount));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), recipient, amount));
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function _assertInitialBalances() private view {
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.balanceOf(SPENDER), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
