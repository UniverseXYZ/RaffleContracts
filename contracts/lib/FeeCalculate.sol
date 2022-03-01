// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

library FeeCalculate {
    struct Fee {
        uint256 remainingValue;
        uint256 feeValue;
    }

    function subFee(uint256 value, uint256 fee) internal pure returns (Fee memory interimFee) {
        if (value > fee) {
            interimFee.remainingValue = value - fee;
            interimFee.feeValue = fee;
        } else {
            interimFee.remainingValue = 0;
            interimFee.feeValue = value;
        }
    }
}
