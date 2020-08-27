#!/usr/bin/env python3

"""
SOURCE FOR DATA AND ASSIGNMENT:
University of Helsinki, course Data Analysis with Python 2020
Link to course description:
https://courses.helsinki.fi/fi/aycsm90004en/135221588

EXERCISE 6 (nonconvex clusters)
This exercise can give four points at maximum!

Read the tab separated file data.tsv from the src folder into a DataFrame. The
dataset has two features X1 and X2, and the label y. Cluster the feature matrix
using DBSCAN with different values for the eps parameter. Use values in
np.arange(0.05, 0.2, 0.05) for clustering. For each clustering, collect the
accuracy score, the number of clusters, and the number of outliers. Return these
values in a DataFrame, where columns and column names are as in the below
example.

Note that DBSCAN uses label -1 to denote outliers, that is, those data points
that didn’t fit well in any cluster. You have to modify the find_permutation
function to handle this: ignore the outlier data points from the accuracy score
computation. In addition, if the number of clusters is not the same as the
number of labels in the original data, set the accuracy score to NaN.

     eps   Score  Clusters  Outliers
0    0.05      ?         ?         ?
1    0.10      ?         ?         ?
2    0.15      ?         ?         ?
3    0.20      ?         ?         ?

Before submitting the solution, you can plot the data set (with clusters
colored) to see what kind of data we are dealing with.

Points are given for each correct column in the result DataFrame.
"""

from typing import List, Tuple

import matplotlib.pyplot as plt
import pandas as pd
import numpy as np
import scipy
from sklearn.cluster import DBSCAN
from sklearn.metrics import accuracy_score


def load_data() -> Tuple[np.array, np.array]:
    """
    Loads the dataset for the assignment.

    Parameters:
    None

    Returns:
    - features: Numpy array of feature columns
    - labels: Numpy vector of corresponding labels
    """
    # Load data
    data = pd.read_csv("src/data.tsv", sep="\t")

    # Create Numpy arrays for features and labels
    features = data.iloc[:, :2].to_numpy()
    labels = data.iloc[:, 2].to_numpy()

    return features, labels


def find_permutation(n_clusters: int, real_labels: np.array,
                     pred_labels: np.array) -> (List[int], np.array):
    """
    Gets a permutation of predicted labels so that the scheme of the model's
    predicted labels matches the scheme of the original labels.

    NOTE: For the purposes of this assignment, we ignore the data points
    that DBSCAN identifies as outliers both from real_labels and pred_labels.
    The implementation itself works fine even if you do not ignore the outliers,
    as they are given a value of -1.

    Parameters:
    - n_clusters: Number of clusters for which to perform the relabeling
    - real_labels: The original labels for each data point
    - labels: The predicted labels for each data point

    Returns:
    - permutation: New labeling scheme for predicted labels to match the scheme
        of labels
    - new_labels: New labeling for predicted labels
    """
    permutation = []

    # For each predicted cluster, we want to assign an new label
    for i in range(n_clusters):

        # Get the points from the predicted clusters with the currently
        # evaluated label
        idx = pred_labels == i

        # Get the corresponding data points from real labels. The new label
        # to use is the most common of the real labels found.
        new_label = scipy.stats.mode(real_labels[idx])[0][0]

        # Append the new label to list. This list will be used to replace the
        # model's assigned labels pointwise.
        permutation.append(new_label)

    # Create a new array of predicted labels with the same labeling scheme as
    # the original labels
    new_labels = [permutation[label]
                  for label in pred_labels]  # permute the labels

    return permutation, new_labels


def train_and_evaluate_dbscan(eps: float, features: np.array, labels: np.array):
    """
    Trains a DBSCAN model with the given eps parameter and features, compares
    results against real labels, and returns evaluation data.

    Model evaluation with different values of eps could be done in practice also
    with sklearn.model_selection.GridSearchCV. However, the assignment calls for
    specific information not available from GridSearchCV to be output, so we are
    using a custom function.

    Parameters:
    - eps: eps parameter value to use when training the DBSCAN model, the max
        distance between to samples to consider them part of the same cluster
    - features: Numpy array of feature data with which to train the DBSCAN model
    - labels: Real labels against which to evaluate the DBSCAN model

    Returns:
    - eps: The eps value used for this run
    - score: The accuracy score with outliers ignored
    - clusters: The number of clusters identified by DBSCAN
    - outliers: The number of outliers identified by DBSCAN
    """

    # Train DBSCAN model
    model = DBSCAN(eps=eps)
    model.fit(features)

    pred_labels = model.labels_
    pred_outliers = pred_labels == -1
    pred_outliers_count = pred_outliers.sum()

    pred_labels_no_ol = pred_labels[np.invert(pred_outliers)]
    pred_clusters_count = np.unique(pred_labels_no_ol).shape[0]

    orig_clusters_count = np.unique(labels).shape[0]

    if pred_clusters_count != orig_clusters_count:
        score = None
    else:
        # Ignore outliers from both original labels and predicted labels for
        # score calculation
        labels_no_ol = labels[np.invert(pred_outliers)]

        new_pred_labels_no_ol = find_permutation(
            pred_clusters_count, labels_no_ol, pred_labels_no_ol)[1]
        score = accuracy_score(new_pred_labels_no_ol, labels_no_ol)

    return eps, score, pred_clusters_count, pred_outliers_count, pred_labels


def nonconvex_clusters() -> pd.DataFrame:
    """
    Evaluates DBSCAN models with different EPS values on a given dataset.

    Also visualizes the clustering results given by DBSCAN.

    Parameters:
    None

    Returns:
    - result_df: Pandas DataFrame with the eps value, accuracy score, and the
        number of clusters and outliers identified by DBSCAN
    """
    features, labels = load_data()

    eps_values = np.arange(0.05, 0.2, 0.05)
    result_df = pd.DataFrame(columns=["eps", "Score", "Clusters", "Outliers"])
    pred_labels_all = np.empty((labels.shape[0], eps_values.shape[0]))

    for i, eps in enumerate(eps_values):
        eps, score, clusters, outliers, pred_labels = \
            train_and_evaluate_dbscan(eps, features, labels)

        result_dict = {
            "eps": eps,
            "Score": score,
            "Clusters": clusters,
            "Outliers": outliers
        }

        result_df = result_df.append(result_dict, ignore_index=True)
        pred_labels_all[:, i] = pred_labels

    fig, ax = plt.subplots(3, 2)
    ax[0, 0].scatter(features[:, 0], features[:, 1], c=labels)
    ax[1, 0].scatter(features[:, 0], features[:, 1], c=pred_labels_all[:, 0])
    ax[1, 1].scatter(features[:, 0], features[:, 1], c=pred_labels_all[:, 1])
    ax[2, 0].scatter(features[:, 0], features[:, 1], c=pred_labels_all[:, 2])
    ax[2, 1].scatter(features[:, 0], features[:, 1], c=pred_labels_all[:, 3])
    plt.show()

    return result_df


def main():
    """
    Main function
    """
    print(nonconvex_clusters())


if __name__ == "__main__":
    main()
