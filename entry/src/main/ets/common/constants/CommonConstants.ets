/*
 * Copyright (c) 2024 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

export class CommonConstants{
  /**
   * The font weight of 700.
   */
  static readonly FONT_WEIGHT_700: number = 700;

  /**
   * Full percent
   */
  static readonly FULL_PERCENT: string = '100%';

  /**
   * The font weight of 500.
   */
  static readonly FONT_WEIGHT_500: number = 500;

  /**
   * The font weight of 400.
   */
  static readonly FONT_WEIGHT_400: number = 400;

  /**
   * Array buffer size.
   */
  static readonly ARRAY_BUFFER_SIZE: number = 4096000;

  /**
   * Model name.
   */
  static readonly MODEL_NAME: string = 'infi_0820_16_1024.ms';

  /**
   * Model input height.
   */
  static readonly MODEL_INPUT_HEIGHT: number = 224;

  /**
   * Model input width.
   */
  static readonly MODEL_INPUT_WIDTH: number = 224;

  /**
   * Labels name map
   */
  static readonly LABELS_NAME_MAP: string[] = [
    'Model1 预测价值', 'Model2 预测价值', 'Model3 预测价值', 'Model4 预测价值', 'Model5 预测价值'];

  /**
   * Means flag
   */
  static readonly MEANS: number[] = [0.485, 0.456, 0.406];

  /**
   * Std flag
   */
  static readonly STDS: number[] = [0.229, 0.224, 0.225];

  /**
   * Ten thousand
   */
  static readonly TEN_THOUSAND: number = 10000;

  /**
   * RGB max value
   */
  static readonly RGB_MAX_VALUE:number = 255;

  /**
   * The max zoom value
   */
  static readonly MAX_ZOOM_VALUE: number = 256;

  /**
   * x-coordinate at the upper left corner of the image
   */
  static readonly X_COORDINATE: number = 16;

  /**
   * y-coordinate at the upper left corner of the image
   */
  static readonly Y_COORDINATE: number = 16;
}