# VoltFi Smart Contract

VoltFi is a decentralized lending and liquidity protocol built on the Stacks blockchain using Clarity smart contracts. This contract allows users to provide liquidity, deposit collateral, borrow STX, repay loans, and liquidate risky positions.

---

## Features

- **Liquidity Provision:**  
  Users can deposit STX to the protocol and receive LP tokens representing their share of the pool. LP tokens can be redeemed for STX at any time.

- **Collateralized Borrowing:**  
  Users can deposit STX as collateral and borrow against it, subject to loan-to-value (LTV) limits.

- **Debt Repayment:**  
  Borrowers can repay their debt partially or fully.

- **Liquidation:**  
  If a borrower's LTV exceeds the liquidation threshold, their position can be liquidated and their collateral claimed.

- **Price Oracle:**  
  The contract maintains a price feed for assets (e.g., STX) to calculate collateral values and LTV ratios.

---

## Key Concepts

- **LP Tokens:**  
  Represent a user's share of the liquidity pool. Minted on deposit, burned on withdrawal.

- **Positions:**  
  Track each user's collateral and debt.

- **LTV (Loan-to-Value):**  
  Ratio of debt to collateral value. Must remain below `MAX-LTV` to avoid liquidation.

- **Liquidation Threshold:**  
  If LTV exceeds this value, the position can be liquidated.

---

## Contract Structure

### Constants

- `MAX-LTV`: Maximum allowed LTV for borrowing (default: 70%).
- `LIQUIDATION-THRESHOLD`: LTV threshold for liquidation (default: 80%).

### Maps

- `lp-balances`: User LP token balances.
- `positions`: User collateral and debt positions.
- `price-feed`: Asset price data.

### Variables

- `total-stx`: Total STX in the protocol.
- `lp-total-supply`: Total LP tokens issued.

---

## Public Functions

### Oracle

- `set-price(symbol, price)`: Set the price for an asset symbol.

### Liquidity Provider (LP)

- `lp-deposit(amount)`: Deposit STX and receive LP tokens.
- `lp-withdraw(lp-amount)`: Redeem LP tokens for STX.

### Vault

- `deposit-collateral(amount)`: Deposit STX as collateral.
- `borrow(amount)`: Borrow STX against collateral.
- `repay-debt(amount)`: Repay borrowed STX.
- `liquidate(target)`: Liquidate a user's position if LTV exceeds the threshold.

---

## Error Codes

- `u400`: Borrowing conditions not met.
- `u402`: Liquidation conditions not met.
- `u500`: Price not found.
- `u501`: Invalid collateral value.
- `u600`: LP deposit transfer failed.
- `u601`: LP withdrawal transfer failed.
- `u602`: Insufficient balance or transfer failed.
- `u603`: Borrow transfer failed.
- `u604`: Repay transfer failed.
- `u605`: No debt to repay.
- `u606`: Liquidation transfer failed.
- `u607`: Zero amount provided.
- `u608`: No position found.
- `u700`: Invalid symbol length.

---

## Usage Example

1. **Deposit STX for LP tokens:**
   ```
   (lp-deposit u1000000)
   ```

2. **Withdraw STX by redeeming LP tokens:**
   ```
   (lp-withdraw u500000)
   ```

3. **Deposit collateral:**
   ```
   (deposit-collateral u1000000)
   ```

4. **Borrow STX:**
   ```
   (borrow u500000)
   ```

5. **Repay debt:**
   ```
   (repay-debt u250000)
   ```

6. **Liquidate risky position:**
   ```
   (liquidate 'SP...target)
   ```

---

## Security Notes

- All transfers use `stx-transfer?` for atomicity.
- LTV checks prevent over-borrowing.
- Only positions exceeding the liquidation threshold can be liquidated.

---

## License

This contract is provided for educational and experimental purposes. Use at your own risk.

---

**Author:**  
Uchenna Okafor  
July 2025
