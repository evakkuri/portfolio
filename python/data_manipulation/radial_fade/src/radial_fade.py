#!/usr/bin/env python3

"""
SOURCE FOR ASSIGNMENT:
University of Helsinki, course Data Analysis with Python 2020
Link to course description:
https://courses.helsinki.fi/fi/aycsm90004en/135221588

EXERCISE 12 (radial fade)
Make program that does fading of an image as earlier, except now not in
horizontal direction but in radial direction. As we move away from the centre of
the image, the pixels fade to black.

Part 1:
- Write function center that returns coordinate pair (center_y, center_x) of the
  image center.
    - Note that these coordinates might not be integers. Example of usage:

        print(center(np.zeros((10, 11, 3))))
        (4.5, 5)

    - The function should work both for two and three dimensional images, that
      is grayscale and color images.

- Write also function radial_distance that returns for image with width w and
  height h an array with shape (h,w), where the number at index (i,j) gives the
  euclidean distance from the point (i,j) to the center of the image.

Part 2.
- Create function scale(a, tmin=0.0, tmax=1.0) that returns a copy of the array
  a with its elements scaled to be in the range [tmin,tmax].

- Using the functions radial_distance and scale write function radial_mask that
  takes an image as a parameter and returns an array with same height and width
  filled with values between 0.0 and 1.0. Do this using the scale function. To
  make the resulting array values near the center of array to be close to 1 and
  closer to the edges of the array are values closer to be 0, subtract the
  previous array from 1.

- Write also function radial_fade that returns the image multiplied by its
  radial mask.

- Test your functions in the main function, which should create, using
  matplotlib, a figure that has three subfigures stacked vertically.
  
On top the original painting.png, in the middle the mask, and on the bottom the
faded image.
"""

from typing import Tuple

import numpy as np
import matplotlib.pyplot as plt


def center(a: np.array) -> Tuple[float, float]:
    """
    Returns the center point of a Numpy array.

    Center point does not necessarily correspond to any single cell in the array,
    take this into account in subsequent steps.

    Parameters:
    - a: Numpy array for which to determine the center point

    Returns:
    - Tuple with the y coordinate and x coordinate of the center point respectively
        (Note the order) 
    """
    return ((a.shape[0] - 1) / 2, (a.shape[1] - 1) / 2)   # note the order: (center_y, center_x)


def radial_distance(a: np.array) -> np.array:
    """
    Returns the Euclidean distance of each Numpy array cell from the center point of the array.

    Parameters:
    - a: Numpy array (should be the same shape as the array to be masked)

    Returns:
    - distances: Numpy array of the same shape as a, with Euclidean distances from array
        center point as values
    """

    # Get center point of array
    center_point = np.array(center(a))

    # Create arrays with pixel locations for distance calculation,
    # starting from 0
    x_coord, y_coord = np.meshgrid(
        np.arange(a.shape[1]), np.arange(a.shape[0]))

    # Calculate Euclidean distance of each pixel from center point
    distances = np.sqrt(
        (y_coord - center_point[0])**2 + (x_coord-center_point[1])**2)

    return distances


def scale(a: np.array) -> np.array:
    """
    Returns a copy of array 'a' with its values scaled to be in the range
    [tmin,tmax].

    Parameters:
    a: Numpy array the values of which are to be scaled
    tmin: Minimum value to which to scale the array values
    tmax: Maximum values to which to scale the array values

    Returns:
    - a_scales: Copy of array a with values scaled to between tmin and tmax
    """

    a_centered = a - np.min(a)
    a_scaled = a_centered / \
        (np.max(a_centered) if np.max(a_centered) > 0 else 1)
    return a_scaled


def radial_mask(a: np.array) -> np.array:
    """
    Returns the inverse of array values.

    Used to inverse the distance matrix calculated for the original array, in
    order to correctly scale cells further from center to black.

    Parameters:
    - a: Array to inverse

    Returns:
    - The inverse of array a
    """
    return 1 - scale(radial_distance(a))


def radial_fade(a: np.array) -> np.array:
    """
    Applies a radial fade mask to a Numpy array (e.g. a picture).

    With a radial fade mask, array cells further away from the center of the
    array as measured by Euclidean distance are scaled closer to zero. With a
    picture, this causes a scaling towards black.

    Parameters:
    - a: Numpy array to which to apply the radial fade mask.

    Returns:
    - Numpy array of same shape as a, with values further away from array center
        scaled towards black
    """
    mask = radial_mask(a)

    if len(a.shape) == 3:
        mask = mask.reshape(mask.shape[0], mask.shape[1], -1)

    return a * mask


def main():
    """
    Main function. Runs some tests.
    """

    img = plt.imread("src/own_picture.png")
    img = img[:, :, :3]
    fade_img = radial_fade(img)

    fig, ax = plt.subplots(1, 3)
    ax[0].imshow(img)
    ax[1].imshow(radial_mask(img))
    ax[2].imshow(fade_img)
    plt.show()


if __name__ == "__main__":
    main()
