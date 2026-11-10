<?php

declare(strict_types=1);

namespace App\Tests;

use App\Calculator;
use PHPUnit\Framework\TestCase;

final class CalculatorTest extends TestCase
{
    public function testAddAdditionneDeuxNombres(): void
    {
        self::assertSame(5, (new Calculator())->add(2, 3));
    }
}
